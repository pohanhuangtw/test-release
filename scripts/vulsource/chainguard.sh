#!/usr/bin/env bash
# Legacy references:
# - scripts/jenkins-ssh-script-vulsource.sh, function download_chainguard_osv_v2_data()
# - scripts/jenkins-ssh-script-vulsource.sh, section "Download chainguard OSV advisories"
# Upstream references:
# - https://advisories.cgr.dev/chainguard/v2/osv/all.json
# - https://advisories.cgr.dev/chainguard/v2/osv/
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

INDEX_URL="https://advisories.cgr.dev/chainguard/v2/osv/all.json"
ADVISORY_BASE_URL="https://advisories.cgr.dev/chainguard/v2/osv"

# Use _lib.sh for staging directory management
FEED="chainguard"
dir=$(begin_output "$FEED")

echo "Fetching Chainguard OSV v2 index..."
curl -fsSL -o "$dir/_index.json" "$INDEX_URL"

if [ ! -s "$dir/_index.json" ]; then
  echo "Failed to fetch index or index is empty" >&2
  exit 1
fi

jq -r '.[].id' "$dir/_index.json" > "$dir/_ids.txt"

if [ ! -s "$dir/_ids.txt" ]; then
  echo "No advisories found in index" >&2
  exit 1
fi

total=$(wc -l < "$dir/_ids.txt")
echo "Found $total advisories, downloading..."

count=0
failed=0
while read -r id; do
  count=$((count + 1))
  url="${ADVISORY_BASE_URL}/${id}.json"
  out="$dir/${id}.json"

  if curl -fsSL --connect-timeout 30 --retry 5 --retry-delay 5 --retry-all-errors -o "$out" "$url"; then
    printf "\r[%d/%d] %s" "$count" "$total" "$id"
  else
    failed=$((failed + 1))
    printf "\n[%d/%d] FAILED: %s\n" "$count" "$total" "$id" >&2
  fi
done < "$dir/_ids.txt"
echo ""

rm -f "$dir/_index.json" "$dir/_ids.txt"

file_count=$(find "$dir" -name '*.json' | wc -l)
echo "Downloaded $file_count / $total advisories ($failed failed)"

if [ "$file_count" -eq 0 ]; then
  echo "No advisories downloaded" >&2
  exit 1
fi

# Create tar.gz archive (flat structure) in the staging directory
output_file="osv-v2.zip"
( cd "$dir" && zip "../$output_file" *.json )

if [ ! -s "$STAGE_DIR/$output_file" ]; then
  echo "Failed to create archive" >&2
  exit 1
fi

echo "Successfully created $(du -h "$STAGE_DIR/$output_file" | cut -f1) archive ($file_count advisories)"

verify_vuls_coverage "$FIXTURES_ROOT/$FEED" "$STAGE_DIR/$output_file"
finish_output "$output_file"
