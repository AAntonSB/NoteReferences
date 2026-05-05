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
enum LatexWorkspaceMode { visual, source, split, pdf }

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
                  ButtonSegment(value: LatexWorkspaceMode.visual, label: Text('Visual'), icon: Icon(Icons.edit_note_rounded)),
                  ButtonSegment(value: LatexWorkspaceMode.source, label: Text('Source'), icon: Icon(Icons.code_rounded)),
                  ButtonSegment(value: LatexWorkspaceMode.split, label: Text('Source + PDF'), icon: Icon(Icons.view_column_outlined)),
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


/// Overleaf-style LaTeX editor surface.
///
/// The LaTeX source remains the canonical document. This widget renders safe,
/// common LaTeX visually while keeping every rendered block source-aware:
/// tapping a rendered block reveals and edits the exact LaTeX source behind it.
/// Unknown, complex, or broken LaTeX falls back to a compact editable source
/// block instead of producing misleading preview garbage.
class LatexHybridEditor extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String title;
  final bool embedded;

  const LatexHybridEditor({
    super.key,
    required this.controller,
    required this.title,
    this.focusNode,
    this.embedded = false,
  });

  @override
  State<LatexHybridEditor> createState() => _LatexHybridEditorState();
}

class _LatexHybridEditorState extends State<LatexHybridEditor> {
  final _activeController = TextEditingController();
  final _activeFocusNode = FocusNode(debugLabel: 'LatexHybridActiveBlock');
  int? _activeStart;
  int? _activeEnd;
  bool _syncingActiveBlock = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleSourceChanged);
    _activeController.addListener(_handleActiveEdited);
    _activeFocusNode.addListener(() {
      if (!_activeFocusNode.hasFocus && mounted) {
        setState(() {
          _activeStart = null;
          _activeEnd = null;
          _activeController.clear();
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant LatexHybridEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleSourceChanged);
      widget.controller.addListener(_handleSourceChanged);
      _clearActiveBlock();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleSourceChanged);
    _activeController.removeListener(_handleActiveEdited);
    _activeController.dispose();
    _activeFocusNode.dispose();
    super.dispose();
  }

  void _handleSourceChanged() {
    final start = _activeStart;
    final end = _activeEnd;
    if (start == null || end == null) return;
    if (start < 0 || end > widget.controller.text.length || start > end) {
      _clearActiveBlock();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _clearActiveBlock() {
    if (!mounted) return;
    setState(() {
      _activeStart = null;
      _activeEnd = null;
      _activeController.clear();
    });
  }

  void _activateBlock(_LatexVisualBlock block) {
    _syncingActiveBlock = true;
    _activeController.text = block.source;
    _activeController.selection = TextSelection.collapsed(offset: _activeController.text.length);
    _syncingActiveBlock = false;
    setState(() {
      _activeStart = block.start;
      _activeEnd = block.end;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _activeFocusNode.requestFocus();
    });
  }

  void _handleActiveEdited() {
    if (_syncingActiveBlock) return;
    final start = _activeStart;
    final end = _activeEnd;
    if (start == null || end == null) return;
    final current = widget.controller.text;
    if (start < 0 || end > current.length || start > end) return;
    final replacement = _activeController.text;
    final next = current.replaceRange(start, end, replacement);
    final selectionOffset = (start + replacement.length).clamp(0, next.length).toInt();
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: selectionOffset),
    );
    _activeEnd = start + replacement.length;
  }

  bool _isActive(_LatexVisualBlock block) {
    final start = _activeStart;
    if (start == null) return false;
    return start >= block.start && start <= block.end;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final parsed = _LatexVisualParser.parse(widget.controller.text);
        final horizontal = widget.embedded ? 12.0 : 32.0;
        final vertical = widget.embedded ? 12.0 : 28.0;
        return ColoredBox(
          color: theme.colorScheme.surfaceContainerLowest,
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: widget.embedded ? 720 : 860),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(widget.embedded ? 12 : 18),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(180)),
                      boxShadow: [
                        if (!widget.embedded)
                          BoxShadow(color: Colors.black.withAlpha(14), blurRadius: 26, offset: const Offset(0, 14)),
                      ],
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: widget.embedded ? 680 : 960),
                      child: Padding(
                        padding: EdgeInsets.all(widget.embedded ? 24 : 46),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (parsed.preamble != null) _PreambleDisclosure(source: parsed.preamble!),
                            if (parsed.blocks.isEmpty)
                              Text(
                                'Start typing LaTeX. Visual mode renders safe blocks and reveals source when you click them.',
                                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              )
                            else
                              for (final block in parsed.blocks)
                                _LatexVisualBlockView(
                                  key: ValueKey('${block.start}-${block.end}-${block.type}-${_isActive(block)}'),
                                  block: block,
                                  active: _isActive(block),
                                  activeController: _activeController,
                                  activeFocusNode: _activeFocusNode,
                                  onTap: () => _activateBlock(block),
                                ),
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
      },
    );
  }
}

class _PreambleDisclosure extends StatelessWidget {
  final String source;

  const _PreambleDisclosure({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        collapsedBackgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        title: const Text('Show document preamble'),
        children: [
          SelectableText(
            source.trim(),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatexVisualBlockView extends StatelessWidget {
  final _LatexVisualBlock block;
  final bool active;
  final TextEditingController activeController;
  final FocusNode activeFocusNode;
  final VoidCallback onTap;

  const _LatexVisualBlockView({
    super.key,
    required this.block,
    required this.active,
    required this.activeController,
    required this.activeFocusNode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (active || block.type == _LatexVisualBlockType.raw || block.type == _LatexVisualBlockType.unsupported || block.broken) {
      return _LatexSourceBlockEditor(
        block: block,
        controller: active ? activeController : null,
        focusNode: active ? activeFocusNode : null,
        readOnly: !active,
        onTap: onTap,
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: _renderVisual(context),
      ),
    );
  }

  Widget _renderVisual(BuildContext context) {
    final theme = Theme.of(context);
    switch (block.type) {
      case _LatexVisualBlockType.section:
        return Text(
          block.text,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        );
      case _LatexVisualBlockType.subsection:
        return Text(
          block.text,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.15),
        );
      case _LatexVisualBlockType.comment:
        return Text(
          block.text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            color: Colors.green.shade700,
          ),
        );
      case _LatexVisualBlockType.center:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final line in block.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Text(
                  line,
                  textAlign: TextAlign.center,
                  style: line == block.lines.first
                      ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)
                      : theme.textTheme.bodyLarge,
                ),
              ),
          ],
        );
      case _LatexVisualBlockType.itemize:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in block.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.only(top: 7), child: Text('•  ')),
                    Expanded(child: _InlineLatexText(line)),
                  ],
                ),
              ),
          ],
        );
      case _LatexVisualBlockType.role:
        return _LatexRoleBlock(lines: block.lines);
      case _LatexVisualBlockType.math:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Math.tex(block.text, textStyle: theme.textTheme.titleMedium),
        );
      case _LatexVisualBlockType.paragraph:
        return _InlineLatexText(block.text);
      case _LatexVisualBlockType.raw:
      case _LatexVisualBlockType.unsupported:
        return const SizedBox.shrink();
    }
  }
}

class _LatexSourceBlockEditor extends StatelessWidget {
  final _LatexVisualBlock block;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool readOnly;
  final VoidCallback onTap;

  const _LatexSourceBlockEditor({
    required this.block,
    required this.controller,
    required this.readOnly,
    required this.onTap,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnsupported = block.type == _LatexVisualBlockType.unsupported;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isUnsupported ? theme.colorScheme.primaryContainer.withAlpha(45) : theme.colorScheme.surfaceContainerHighest.withAlpha(90),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUnsupported ? theme.colorScheme.primary.withAlpha(90) : theme.colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: readOnly ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isUnsupported || block.broken) ...[
                  Row(
                    children: [
                      Icon(
                        block.broken ? Icons.warning_amber_rounded : Icons.code_rounded,
                        size: 16,
                        color: block.broken ? theme.colorScheme.error : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          block.broken ? 'LaTeX source needs attention' : 'Unsupported LaTeX block — edit as source',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: block.broken ? theme.colorScheme.error : theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (readOnly)
                  SelectableText(
                    block.source,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: theme.colorScheme.onSurface,
                      height: 1.35,
                    ),
                  )
                else
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: block.source.contains('\n') ? null : 1,
                    maxLines: null,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: theme.colorScheme.onSurface,
                      height: 1.35,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
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

class _InlineLatexText extends StatelessWidget {
  final String text;

  const _InlineLatexText(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectableText.rich(
      TextSpan(
        children: _inlineSpans(text, theme),
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
      ),
    );
  }

  static List<InlineSpan> _inlineSpans(String value, ThemeData theme) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\\textbf\{([^{}]*)\}|\\emph\{([^{}]*)\}|\\textit\{([^{}]*)\}|\\href\{([^{}]*)\}\{([^{}]*)\}|\\url\{([^{}]*)\}|\$([^$]+)\$)');
    var cursor = 0;
    for (final match in regex.allMatches(value)) {
      if (match.start > cursor) spans.add(TextSpan(text: value.substring(cursor, match.start)));
      if (match.group(2) != null) {
        spans.add(TextSpan(text: match.group(2), style: const TextStyle(fontWeight: FontWeight.w800)));
      } else if (match.group(3) != null || match.group(4) != null) {
        spans.add(TextSpan(text: match.group(3) ?? match.group(4), style: const TextStyle(fontStyle: FontStyle.italic)));
      } else if (match.group(6) != null) {
        spans.add(TextSpan(text: match.group(6), style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline)));
      } else if (match.group(7) != null) {
        spans.add(TextSpan(text: match.group(7), style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline)));
      } else if (match.group(8) != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Math.tex(match.group(8)!, textStyle: theme.textTheme.bodyLarge),
          ),
        ));
      } else {
        spans.add(TextSpan(text: match.group(0)));
      }
      cursor = match.end;
    }
    if (cursor < value.length) spans.add(TextSpan(text: value.substring(cursor)));
    return spans.isEmpty ? [TextSpan(text: value)] : spans;
  }
}

class _LatexRoleBlock extends StatelessWidget {
  final List<String> lines;

  const _LatexRoleBlock({required this.lines});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = lines.isNotEmpty ? lines[0] : '';
    final date = lines.length > 1 ? lines[1] : '';
    final company = lines.length > 2 ? lines[2] : '';
    final location = lines.length > 3 ? lines[3] : '';
    final bullets = lines.length > 4 ? lines.sublist(4) : const <String>[];
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  role,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (date.isNotEmpty)
                Text(date, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          if (company.isNotEmpty || location.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              [company, location].where((part) => part.trim().isNotEmpty).join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700),
            ),
          ],
          if (bullets.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final bullet in bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.only(top: 7), child: Text('•  ')),
                    Expanded(child: _InlineLatexText(bullet)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LatexVisualDocument {
  const _LatexVisualDocument({required this.blocks, this.preamble});
  final List<_LatexVisualBlock> blocks;
  final String? preamble;
}

class _LatexVisualBlock {
  const _LatexVisualBlock({
    required this.type,
    required this.source,
    required this.start,
    required this.end,
    this.text = '',
    this.lines = const [],
    this.broken = false,
  });

  final _LatexVisualBlockType type;
  final String source;
  final int start;
  final int end;
  final String text;
  final List<String> lines;
  final bool broken;
}

enum _LatexVisualBlockType { section, subsection, paragraph, comment, center, itemize, role, math, unsupported, raw }

class _LatexVisualParser {
  static _LatexVisualDocument parse(String source) {
    if (source.trim().isEmpty) return const _LatexVisualDocument(blocks: []);
    final bodyRange = _documentBodyRange(source);
    final preamble = bodyRange == null ? null : source.substring(0, bodyRange.start);
    final parseStart = bodyRange?.start ?? 0;
    final parseEnd = bodyRange?.end ?? source.length;
    final body = source.substring(parseStart, parseEnd);
    final blocks = <_LatexVisualBlock>[];
    var cursor = 0;

    while (cursor < body.length) {
      final whitespace = RegExp(r'\s+').matchAsPrefix(body, cursor);
      if (whitespace != null) {
        cursor = whitespace.end;
        continue;
      }

      final absolute = parseStart + cursor;
      final remaining = body.substring(cursor);

      if (remaining.startsWith('%')) {
        final lineEnd = _lineEnd(body, cursor);
        final raw = body.substring(cursor, lineEnd);
        blocks.add(_LatexVisualBlock(
          type: _LatexVisualBlockType.comment,
          source: raw,
          start: absolute,
          end: parseStart + lineEnd,
          text: raw,
        ));
        cursor = lineEnd;
        continue;
      }

      final section = _parseSection(body, cursor, parseStart);
      if (section != null) {
        blocks.add(section);
        cursor = section.end - parseStart;
        continue;
      }

      final env = _parseEnvironment(body, cursor, parseStart);
      if (env != null) {
        blocks.add(env);
        cursor = env.end - parseStart;
        continue;
      }

      final role = _parseCommandWithArgs(body, cursor, parseStart, 'role', expectedArgs: 5);
      if (role != null) {
        blocks.add(role);
        cursor = role.end - parseStart;
        continue;
      }

      final displayMath = _parseDisplayMath(body, cursor, parseStart);
      if (displayMath != null) {
        blocks.add(displayMath);
        cursor = displayMath.end - parseStart;
        continue;
      }

      if (body.codeUnitAt(cursor) == 92) {
        final lineEnd = _lineEnd(body, cursor);
        final raw = body.substring(cursor, lineEnd);
        blocks.add(_LatexVisualBlock(
          type: _LatexVisualBlockType.raw,
          source: raw,
          start: absolute,
          end: parseStart + lineEnd,
          broken: raw.contains('{') && !_hasBalancedBraces(raw),
        ));
        cursor = lineEnd;
        continue;
      }

      final paragraphEnd = _paragraphEnd(body, cursor);
      final raw = body.substring(cursor, paragraphEnd);
      final cleaned = _cleanParagraph(raw);
      if (cleaned.trim().isNotEmpty) {
        blocks.add(_LatexVisualBlock(
          type: _LatexVisualBlockType.paragraph,
          source: raw,
          start: absolute,
          end: parseStart + paragraphEnd,
          text: cleaned,
          broken: !_hasBalancedBraces(raw),
        ));
      }
      cursor = paragraphEnd;
    }

    return _LatexVisualDocument(blocks: blocks, preamble: preamble?.trim().isEmpty == true ? null : preamble);
  }

  static _TextRange? _documentBodyRange(String source) {
    final begin = RegExp(r'\\begin\{document\}').firstMatch(source);
    if (begin == null) return null;
    final end = RegExp(r'\\end\{document\}').firstMatch(source.substring(begin.end));
    if (end == null) return _TextRange(begin.end, source.length);
    return _TextRange(begin.end, begin.end + end.start);
  }

  static _LatexVisualBlock? _parseSection(String body, int cursor, int offset) {
    final command = RegExp(r'\\(section|subsection)\*?').matchAsPrefix(body, cursor);
    if (command == null) return null;
    final arg = _readBraceGroup(body, command.end);
    if (arg == null) {
      final lineEnd = _lineEnd(body, cursor);
      return _LatexVisualBlock(
        type: _LatexVisualBlockType.raw,
        source: body.substring(cursor, lineEnd),
        start: offset + cursor,
        end: offset + lineEnd,
        broken: true,
      );
    }
    final name = command.group(1) == 'section' ? _LatexVisualBlockType.section : _LatexVisualBlockType.subsection;
    return _LatexVisualBlock(
      type: name,
      source: body.substring(cursor, arg.end),
      start: offset + cursor,
      end: offset + arg.end,
      text: _cleanInline(arg.content),
    );
  }

  static _LatexVisualBlock? _parseEnvironment(String body, int cursor, int offset) {
    final begin = RegExp(r'\\begin\{([A-Za-z*]+)\}([^\n]*)').matchAsPrefix(body, cursor);
    if (begin == null) return null;
    final name = begin.group(1) ?? '';
    final endPattern = '\\end{$name}';
    final endIndex = body.indexOf(endPattern, begin.end);
    if (endIndex < 0) {
      final lineEnd = _lineEnd(body, cursor);
      return _LatexVisualBlock(
        type: _LatexVisualBlockType.raw,
        source: body.substring(cursor, lineEnd),
        start: offset + cursor,
        end: offset + lineEnd,
        broken: true,
      );
    }
    final end = endIndex + endPattern.length;
    final raw = body.substring(cursor, end);
    final inner = body.substring(begin.end, endIndex);

    if (name == 'center') {
      return _LatexVisualBlock(
        type: _LatexVisualBlockType.center,
        source: raw,
        start: offset + cursor,
        end: offset + end,
        lines: _centerLines(inner),
      );
    }
    if (name == 'itemize' || name == 'enumerate') {
      return _LatexVisualBlock(
        type: _LatexVisualBlockType.itemize,
        source: raw,
        start: offset + cursor,
        end: offset + end,
        lines: _items(inner),
      );
    }
    if (name == 'tabular' || name == 'tabularx' || name == 'array' || name == 'table') {
      return _LatexVisualBlock(
        type: _LatexVisualBlockType.unsupported,
        source: raw,
        start: offset + cursor,
        end: offset + end,
        text: name,
      );
    }
    return _LatexVisualBlock(
      type: _LatexVisualBlockType.raw,
      source: raw,
      start: offset + cursor,
      end: offset + end,
    );
  }

  static _LatexVisualBlock? _parseCommandWithArgs(String body, int cursor, int offset, String command, {required int expectedArgs}) {
    final cmd = RegExp('\\\\$command').matchAsPrefix(body, cursor);
    if (cmd == null) return null;
    var pos = cmd.end;
    final args = <String>[];
    for (var i = 0; i < expectedArgs; i++) {
      final arg = _readBraceGroup(body, pos);
      if (arg == null) {
        final lineEnd = _lineEnd(body, cursor);
        return _LatexVisualBlock(
          type: _LatexVisualBlockType.raw,
          source: body.substring(cursor, lineEnd),
          start: offset + cursor,
          end: offset + lineEnd,
          broken: true,
        );
      }
      args.add(arg.content);
      pos = arg.end;
      while (pos < body.length && RegExp(r'\s').hasMatch(body[pos])) {
        if (body[pos] == '\n' && pos + 1 < body.length && body[pos + 1] == '\n') break;
        pos++;
      }
    }
    final roleLines = <String>[
      _cleanInline(args[0]),
      _cleanInline(args[1]),
      _cleanInline(args[2]),
      _cleanInline(args[3]),
      ..._items(args[4]),
    ].where((line) => line.trim().isNotEmpty).toList();
    return _LatexVisualBlock(
      type: _LatexVisualBlockType.role,
      source: body.substring(cursor, pos),
      start: offset + cursor,
      end: offset + pos,
      lines: roleLines,
    );
  }

  static _LatexVisualBlock? _parseDisplayMath(String body, int cursor, int offset) {
    if (body.startsWith(r'\[', cursor)) {
      final end = body.indexOf(r'\]', cursor + 2);
      if (end < 0) return null;
      return _LatexVisualBlock(
        type: _LatexVisualBlockType.math,
        source: body.substring(cursor, end + 2),
        start: offset + cursor,
        end: offset + end + 2,
        text: body.substring(cursor + 2, end).trim(),
      );
    }
    if (body.startsWith(r'$$', cursor)) {
      final end = body.indexOf(r'$$', cursor + 2);
      if (end < 0) return null;
      return _LatexVisualBlock(
        type: _LatexVisualBlockType.math,
        source: body.substring(cursor, end + 2),
        start: offset + cursor,
        end: offset + end + 2,
        text: body.substring(cursor + 2, end).trim(),
      );
    }
    return null;
  }

  static List<String> _centerLines(String inner) {
    return inner
        .replaceAll(r'\\', '\n')
        .split('\n')
        .map(_cleanInline)
        .where((line) => line.trim().isNotEmpty)
        .toList();
  }

  static List<String> _items(String inner) {
    final parts = inner.split(RegExp(r'\\item\s*'));
    return parts
        .map(_cleanParagraph)
        .where((line) => line.trim().isNotEmpty)
        .toList();
  }

  static int _lineEnd(String value, int start) {
    final next = value.indexOf('\n', start);
    return next < 0 ? value.length : next;
  }

  static int _paragraphEnd(String value, int start) {
    var pos = start;
    while (pos < value.length) {
      if (pos > start && value.startsWith('\n\n', pos)) return pos;
      if (pos > start && value.codeUnitAt(pos) == 92) {
        final previous = pos > 0 ? value[pos - 1] : '';
        if (previous == '\n') return pos;
      }
      pos++;
    }
    return value.length;
  }

  static _BraceGroup? _readBraceGroup(String value, int start) {
    var pos = start;
    while (pos < value.length && RegExp(r'\s').hasMatch(value[pos])) {
      pos++;
    }
    if (pos >= value.length || value[pos] != '{') return null;
    var depth = 0;
    for (var i = pos; i < value.length; i++) {
      final escaped = i > 0 && value.codeUnitAt(i - 1) == 92;
      if (escaped) continue;
      if (value[i] == '{') {
        depth++;
      } else if (value[i] == '}') {
        depth--;
        if (depth == 0) return _BraceGroup(value.substring(pos + 1, i), i + 1);
      }
    }
    return null;
  }

  static bool _hasBalancedBraces(String value) => _balance(value) == 0;

  static int _balance(String value) {
    var depth = 0;
    for (var i = 0; i < value.length; i++) {
      final escaped = i > 0 && value.codeUnitAt(i - 1) == 92;
      if (escaped) continue;
      if (value[i] == '{') depth++;
      if (value[i] == '}') depth--;
      if (depth < 0) return depth;
    }
    return depth;
  }

  static String _cleanParagraph(String raw) {
    return raw
        .replaceAll(r'\\', '\n')
        .split('\n')
        .map(_cleanInline)
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  }

  static String _cleanInline(String raw) {
    var text = raw.trim();
    text = text.replaceAll(RegExp(r'\[[0-9.]+\s*(pt|em|ex|mm|cm|in)\]'), '');
    text = text.replaceAll(RegExp(r'\\(?:quad|qquad|,|;|:|!)'), ' ');
    text = text.replaceAllMapped(
      RegExp(r'\{\\(?:Large|LARGE|huge|Huge|large|small|footnotesize|scriptsize|normalsize)\s+([^{}]*)\}'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(RegExp(r'\\(?:Large|LARGE|huge|Huge|large|small|footnotesize|scriptsize|normalsize)\s+([^\\\n]*)'), (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(RegExp(r'\\href\{([^{}]*)\}\{([^{}]*)\}'), (m) => m.group(2) ?? m.group(1) ?? '');
    text = text.replaceAllMapped(RegExp(r'\\url\{([^{}]*)\}'), (m) => m.group(1) ?? '');
    text = text.replaceAll(r'\&', '&');
    text = text.replaceAll(r'\%', '%');
    text = text.replaceAll(r'\#', '#');
    text = text.replaceAll(r'\_', '_');
    return text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }
}

class _TextRange {
  const _TextRange(this.start, this.end);
  final int start;
  final int end;
}

class _BraceGroup {
  const _BraceGroup(this.content, this.end);
  final String content;
  final int end;
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

