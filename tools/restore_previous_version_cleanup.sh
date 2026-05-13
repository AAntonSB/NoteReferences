#!/usr/bin/env bash
set -euo pipefail

# Phase 13C restore cleanup.
# Run from the project root.

rm -rf lib/features/writer/presentation/paged_document
rmdir lib/features/writer/presentation 2>/dev/null || true
rmdir lib/features/writer 2>/dev/null || true
rm -f PHASE_13C_INTEGRATION_NOTES.md README_PHASE_13C.md README_PHASE_13AB.md

echo "Restore cleanup complete. Now run: flutter analyze"
