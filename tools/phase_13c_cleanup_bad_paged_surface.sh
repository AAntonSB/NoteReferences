#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BAD_FILE="$ROOT_DIR/lib/features/text_system/page/text_system_paged_document_surface.dart"

if [ -f "$BAD_FILE" ]; then
  rm "$BAD_FILE"
  echo "Removed unstable paged projection: $BAD_FILE"
else
  echo "No unstable paged projection file found."
fi

echo "Run: flutter analyze"
