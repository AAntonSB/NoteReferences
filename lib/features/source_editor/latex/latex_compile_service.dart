import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SourceLatexCompileResult {
  const SourceLatexCompileResult({
    required this.success,
    required this.log,
    this.pdfPath,
    this.compiler,
    this.sourcePath,
    this.workDirectory,
    this.duration,
    this.startedAt,
    this.completedAt,
  });

  final bool success;
  final String log;
  final String? pdfPath;
  final String? compiler;
  final String? sourcePath;
  final String? workDirectory;
  final Duration? duration;
  final DateTime? startedAt;
  final DateTime? completedAt;

  String get durationLabel {
    final value = duration;
    if (value == null) return '';
    final seconds = value.inMilliseconds / 1000;
    return seconds < 10 ? '${seconds.toStringAsFixed(1)}s' : '${seconds.round()}s';
  }
}

/// Reusable compiler bridge for the new source-aware editor subsystem.
///
/// This service is intentionally UI-agnostic. It writes the canonical LaTeX
/// source into a stable per-document build directory, compiles it with a local
/// bundled Tectonic when available, then falls back to PATH compilers.
class SourceLatexCompileService {
  const SourceLatexCompileService._();

  static const List<String> _pathCompilerPreference = <String>[
    'tectonic',
    'pdflatex',
    'xelatex',
    'lualatex',
  ];

  static Future<SourceLatexCompileResult> compile({
    required String documentId,
    required String title,
    required String source,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final safeStem = _safeStem(documentId.isEmpty ? title : documentId);
    final workDir = await _persistentBuildDirectory(safeStem);
    await workDir.create(recursive: true);

    final sourcePath = p.join(workDir.path, 'main.tex');
    final pdfPath = p.join(workDir.path, 'main.pdf');
    final texSource = _ensureCompleteDocument(source);
    await File(sourcePath).writeAsString(texSource, flush: true);

    try {
      final stalePdf = File(pdfPath);
      if (await stalePdf.exists()) await stalePdf.delete();
    } catch (_) {
      // Non-fatal. The compiler will either overwrite or fail with a log.
    }

    final compiler = await findAvailableCompiler();
    if (compiler == null) {
      stopwatch.stop();
      return SourceLatexCompileResult(
        success: false,
        sourcePath: sourcePath,
        workDirectory: workDir.path,
        duration: stopwatch.elapsed,
        startedAt: startedAt,
        completedAt: DateTime.now(),
        log: [
          'No LaTeX compiler was found.',
          '',
          'The source-aware editor checks for bundled Tectonic first:',
          '- ./tectonic.exe',
          '- ./bin/tectonic.exe',
          '- ./tools/tectonic/tectonic.exe',
          '- ./vendor/tectonic/tectonic.exe',
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

    final log = StringBuffer()
      ..writeln('Build directory: ${workDir.path}')
      ..writeln('Source: $sourcePath')
      ..writeln('Compiler: ${_displayCompilerName(compiler)}')
      ..writeln('');

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
      final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return 124;
      });
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      if (stdout.trim().isNotEmpty) log.writeln(stdout.trimRight());
      if (stderr.trim().isNotEmpty) log.writeln(stderr.trimRight());
      log.writeln('Exit code: $exitCode');
      return exitCode;
    }

    var exitCode = await runCompiler();
    if (exitCode == 0 && !_isCompiler(compiler, 'tectonic')) {
      exitCode = await runCompiler();
    }

    final pdfExists = await File(pdfPath).exists();
    stopwatch.stop();
    log
      ..writeln('')
      ..writeln('Duration: ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');

    return SourceLatexCompileResult(
      success: exitCode == 0 && pdfExists,
      pdfPath: pdfExists ? pdfPath : null,
      compiler: _displayCompilerName(compiler),
      sourcePath: sourcePath,
      workDirectory: workDir.path,
      duration: stopwatch.elapsed,
      startedAt: startedAt,
      completedAt: DateTime.now(),
      log: log.toString().trim().isEmpty ? 'No compiler log was produced.' : log.toString(),
    );
  }

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
        candidates
          ..add(p.join(root, name))
          ..add(p.join(root, 'bin', name))
          ..add(p.join(root, 'tools', name))
          ..add(p.join(root, 'tools', 'tectonic', name))
          ..add(p.join(root, 'vendor', name))
          ..add(p.join(root, 'vendor', 'tectonic', name));
      }

      var current = Directory(root);
      for (var i = 0; i < 7; i++) {
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
        for (final name in names) {
          candidates
            ..add(p.join(current.path, name))
            ..add(p.join(current.path, 'bin', name))
            ..add(p.join(current.path, 'tools', 'tectonic', name))
            ..add(p.join(current.path, 'vendor', 'tectonic', name));
        }
      }
    }

    final existing = <String>[];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) existing.add(candidate);
    }
    return existing;
  }

  static Future<Directory> _persistentBuildDirectory(String safeStem) async {
    try {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'source_editor_latex_builds', safeStem));
    } catch (_) {
      final tempRoot = await getTemporaryDirectory();
      return Directory(p.join(tempRoot.path, 'source_editor_latex_builds', safeStem));
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
\\usepackage{hyperref}
\\usepackage{tabularx}
\\usepackage[margin=1in]{geometry}
\\newcommand{\\role}[5]{\\noindent\\textbf{#1}\\hfill #2\\\\\\emph{#3 -- #4}\\\\#5\\par\\medskip}
\\newcommand{\\education}[5]{\\noindent\\textbf{#1}\\hfill #2\\\\\\emph{#3 -- #4}\\\\#5\\par\\medskip}
\\newcommand{\\project}[3]{\\noindent\\textbf{#1}\\hfill #2\\\\#3\\par\\medskip}
\\newcommand{\\skillrow}[2]{\\noindent\\textbf{#1:} #2\\par}
\\newcommand{\\cvitem}[2]{\\noindent\\textbf{#1:} #2\\par}
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
    if (safe.isEmpty) return 'latex-document';
    return safe.substring(0, math.min(safe.length, 64));
  }
}
