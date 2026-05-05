import 'package:flutter/material.dart';

import '../core/source_document_controller.dart';
import '../core/source_editor_configuration.dart';
import '../latex/latex_compile_service.dart';
import '../parsers/latex_source_parser.dart';
import 'latex_compile_output_pane.dart';
import 'source_aware_editor.dart';

class LatexSourceEditorLabScreen extends StatefulWidget {
  const LatexSourceEditorLabScreen({super.key});

  @override
  State<LatexSourceEditorLabScreen> createState() => _LatexSourceEditorLabScreenState();
}

class _LatexSourceEditorLabScreenState extends State<LatexSourceEditorLabScreen> {
  late final SourceDocumentController _controller;
  SourceEditorConfiguration _configuration = const SourceEditorConfiguration();
  final LatexSourceParser _parser = LatexSourceParser();
  SourceLatexCompileResult? _compileResult;
  bool _isCompiling = false;

  @override
  void initState() {
    super.initState();
    _controller = SourceDocumentController(source: _sampleLatex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }


  Future<void> _compilePdf() async {
    if (_isCompiling) return;
    setState(() => _isCompiling = true);
    final result = await SourceLatexCompileService.compile(
      documentId: 'latex-source-editor-lab',
      title: 'LaTeX source editor lab',
      source: _controller.source,
    );
    if (!mounted) return;
    setState(() {
      _compileResult = result;
      _isCompiling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LaTeX source-aware editor lab'),
        actions: [
          TextButton.icon(
            onPressed: _isCompiling ? null : _compilePdf,
            icon: _isCompiling
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_isCompiling ? 'Compiling…' : 'Compile PDF'),
          ),
          IconButton(
            tooltip: 'Save snapshot',
            onPressed: () => _controller.saveSnapshot(label: 'LaTeX lab snapshot'),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SourceEditorToolbar(
              configuration: _configuration,
              onChanged: (next) => setState(() => _configuration = next),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SourceAwareEditor(
              controller: _controller,
              parser: _parser,
              configuration: _configuration,
              onConfigurationChanged: (next) => setState(() => _configuration = next),
              outputPane: LatexCompileOutputPane(
                result: _compileResult,
                isCompiling: _isCompiling,
                onCompile: _compilePdf,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _sampleLatex = r'''
% ---------- Header ----------
\begin{center}
{\LARGE \textbf{Anton Bergqvist}}\\
Full-Stack Developer\\
Malmö, Sweden | \href{mailto:anton@example.com}{anton@example.com}
\end{center}

% ---------- Profile ----------
\section*{Profile}
Full-stack developer with professional experience from product teams and backend services.

% ---------- Technical Skills ----------
\begin{tabularx}{\textwidth}{@{}l X @{}}
\textbf{Frontend:} & JavaScript, TypeScript, React, Vue \\
\textbf{Backend:} & C\#, .NET, SQL \\
\end{tabularx}

% ---------- Experience ----------
\section*{Professional Experience}
\role
{Full-Stack Developer}
{Jan 2022 -- Dec 2024}
{CDON}
{Malmö, Sweden}
{\begin{itemize}
\item Developed full-stack e-commerce features.
\item Worked with C\#, .NET, SQL, and Azure.
\end{itemize}}
''';
