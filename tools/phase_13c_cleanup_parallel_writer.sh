#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARALLEL_WRITER="$ROOT_DIR/lib/features/writer/presentation/paged_document"
BAD_PAGED_SURFACE="$ROOT_DIR/lib/features/text_system/page/text_system_paged_document_surface.dart"

if [ -d "$PARALLEL_WRITER" ]; then
  rm -rf "$PARALLEL_WRITER"
  echo "Removed accidental parallel paged writer: $PARALLEL_WRITER"
else
  echo "No accidental parallel paged writer folder found."
fi

if [ -f "$BAD_PAGED_SURFACE" ]; then
  rm "$BAD_PAGED_SURFACE"
  echo "Removed unstable page-local TextField projection: $BAD_PAGED_SURFACE"
else
  echo "No unstable page-local projection file found."
fi

echo "Next: flutter analyze"
