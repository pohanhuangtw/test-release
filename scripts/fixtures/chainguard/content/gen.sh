#!/usr/bin/env bash
set -euo pipefail

INPUT_PATH="${1:-${VERIFY_TARGET_PATH:-${EXTRACT_CHAINGUARD_PATH:-}}}"
EXTRACT_DIR="${VERIFY_EXTRACT_DIR:-${EXTRACT_CHAINGUARD_DIR:-}}"

_extract_cves_from_json_stream() {
  jq -r '
    [((.upstream // [])[]?), ((.aliases // [])[]?)]
    | map(select(type == "string" and test("^CVE-")))
    | .[]
  '
}

if [ -n "$INPUT_PATH" ] && [ -f "$INPUT_PATH" ]; then
  command -v unzip >/dev/null 2>&1 || { echo "unzip is required" >&2; exit 1; }
  command -v jq    >/dev/null 2>&1 || { echo "jq is required"    >&2; exit 1; }

  if ! unzip -Z1 "$INPUT_PATH" 'CGA-*.json' >/dev/null 2>&1; then
    echo "No CGA-*.json advisories found in $INPUT_PATH" >&2
    exit 1
  fi

  unzip -Z1 "$INPUT_PATH" 'CGA-*.json' \
    | while read -r path; do
        unzip -p "$INPUT_PATH" "$path"
      done \
    | _extract_cves_from_json_stream \
    | sort -u
  exit 0
fi

if [ -n "$EXTRACT_DIR" ] && [ -d "$EXTRACT_DIR" ]; then
  command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

  find "$EXTRACT_DIR" -type f -name 'CGA-*.json' -print0 \
    | sort -z \
    | xargs -0 cat \
    | _extract_cves_from_json_stream \
    | sort -u
  exit 0
fi

echo "Usage: $0 <osv-v2.zip>" >&2
echo "Or set VERIFY_TARGET_PATH to a zip, VERIFY_EXTRACT_DIR to an extracted directory," >&2
echo "or use the legacy EXTRACT_CHAINGUARD_PATH / EXTRACT_CHAINGUARD_DIR variables." >&2
exit 1
