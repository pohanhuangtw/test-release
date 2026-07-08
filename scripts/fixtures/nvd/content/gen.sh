#!/usr/bin/env bash
set -euo pipefail

INPUT_PATH="${1:-${VERIFY_TARGET_PATH:-}}"

if [ -n "$INPUT_PATH" ] && [ -f "$INPUT_PATH" ]; then
  if [[ "$INPUT_PATH" == *.gz ]]; then
    gunzip -c "$INPUT_PATH" |
      grep -o '"id"[[:space:]]*:[[:space:]]*"CVE-[0-9]\{4\}-[0-9]\+"' |
      grep -o 'CVE-[0-9]\{4\}-[0-9]\+' |
      LC_ALL=C sort -u
  else
    jq -r '.vulnerabilities[]?.cve.id' "$INPUT_PATH" 2>/dev/null | sort -u
  fi
  exit 0
fi

echo "Usage: $0 <"$INPUT_PATH">" >&2
echo "Or set VERIFY_TARGET_PATH to a file, or VERIFY_EXTRACT_DIR to an extracted directory." >&2
exit 1
