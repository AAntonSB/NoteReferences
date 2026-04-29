import 'package:flutter/material.dart';

import '../sidecar_sync_models.dart';

class SyncDebugOverlay extends StatelessWidget {
  final SyncDebugState state;

  const SyncDebugOverlay({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String f(double value) => value.toStringAsFixed(2);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: Container(
        width: 290,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: DefaultTextStyle(
          style: theme.textTheme.bodySmall!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sync debug',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text('Mode: ${state.mode}'),
              Text('Mapped page: ${state.pageNumber}'),
              Text('PDF anchor Y: ${f(state.pdfAnchorY)}'),
              Text('PDF segment top: ${f(state.pdfSegmentTop)}'),
              Text('PDF segment height: ${f(state.pdfSegmentHeight)}'),
              Text('Segment progress: ${f(state.segmentProgress * 100)}%'),
              Text('Sidecar anchor Y: ${f(state.sidecarAnchorY)}'),
              Text('Target offset: ${f(state.targetOffset)}'),
              Text('Actual before: ${f(state.actualBefore)}'),
              Text('Actual after: ${f(state.actualAfter)}'),
              Text(
                'Correction: ${f(state.correctionBeforeJump)} px',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: state.correctionBeforeJump.abs() > 2
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}