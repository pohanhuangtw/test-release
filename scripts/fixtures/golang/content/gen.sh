#!/usr/bin/env bash
set -euo pipefail

INPUT_PATH="${1:-${VERIFY_TARGET_PATH:-}}"
EXTRACT_DIR="${VERIFY_EXTRACT_DIR:-}"

if [ -n "$INPUT_PATH" ] && [ -f "$INPUT_PATH" ]; then
  unzip -Z1 "$INPUT_PATH" 'GO-*.json' \
    | sed 's#.*/##; s/\.json$//' \
    | sort -u
  exit 0
fi

if [ -n "$EXTRACT_DIR" ] && [ -d "$EXTRACT_DIR" ]; then
  find "$EXTRACT_DIR" -type f -name 'GO-*.json' -printf '%f\n' \
    | sed 's/\.json$//' \
    | sort -u
  exit 0
fi

echo "Usage: $0 <golang-osv.zip>" >&2
echo "Or set VERIFY_TARGET_PATH to a zip, or VERIFY_EXTRACT_DIR to an extracted directory." >&2
exit 1
