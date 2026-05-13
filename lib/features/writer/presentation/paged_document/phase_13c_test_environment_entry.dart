import 'package:flutter/material.dart';

import 'phase_13c_writer_test_screen.dart';

/// Drop this widget into your existing test/lab environment menu.
///
/// It avoids assuming your current route registry shape. Use it as either:
///
/// ```dart
/// const Phase13CTestEnvironmentEntry()
/// ```
///
/// or wire the destination directly:
///
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute(
///     builder: (_) => const Phase13CWriterTestScreen(),
///   ),
/// );
/// ```
class Phase13CTestEnvironmentEntry extends StatelessWidget {
  const Phase13CTestEnvironmentEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.article_outlined),
        title: const Text('Phase 13C — Paged Writer Reflow'),
        subtitle: const Text(
          'Bidirectional page reflow, canonical text slices, academic page lab.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const Phase13CWriterTestScreen(),
            ),
          );
        },
      ),
    );
  }
}
