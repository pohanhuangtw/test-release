#!/usr/bin/env bash
# Upstream references:
# - https://nvd.nist.gov/developers/vulnerabilities
# - https://nvd.nist.gov/feeds/json/cve/2.0/
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

BASE_URL="${BASE_URL:-https://nvd.nist.gov/feeds/json/cve/2.0}"
START_YEAR="${START_YEAR:-2002}"
END_YEAR="${END_YEAR:-$(date -u +%Y)}"

log() {
  echo "[nvd] $*"
}

download_feed() {
  local url="$1"
  local out="$2"
  local err_file="$3"

  local curl_args=(
    -fL
    --silent
    --show-error
    --retry 10
    --retry-all-errors
    --retry-delay 10
    --connect-timeout 300
    -o "$out"
    "$url"
  )

  if [ -n "${NVD_KEY:-}" ]; then
    curl_args=(-H "apiKey: ${NVD_KEY}" "${curl_args[@]}")
  fi

  if curl "${curl_args[@]}" 2>"$err_file"; then
    return 0
  fi

  rm -f "$out"
  return 1
}

# Download to temp dir
feeds_dir="${STAGE_DIR}/nvd-feeds"
mkdir -p "$feeds_dir"

log "Downloading NVD feeds from $START_YEAR to $END_YEAR"

for year in $(seq "$START_YEAR" "$END_YEAR"); do
  file="nvdcve-2.0-${year}.json.gz"
  url="${BASE_URL}/${file}"
  out="$feeds_dir/$file"
  err_file="${feeds_dir}/${file}.err"

  log "Downloading $file"
  if download_feed "$url" "$out" "$err_file" && [ -s "$out" ]; then
    log "OK $file ($(du -h "$out" | awk '{print $1}'))"
    rm -f "$err_file"
  else
    log "FAILED $file"
    if [ -s "$err_file" ]; then
      sed 's/^/[nvd] curl: /' "$err_file" >&2
    fi
    rm -f "$out"
  fi
done

file_count=$(find "$feeds_dir" -name "*.json.gz" | wc -l)
log "Downloaded $file_count feed files"

if [ "$file_count" -eq 0 ]; then
  log "No feeds downloaded, exiting"
  exit 1
fi

log "Merging feeds"
vulns_file="${STAGE_DIR}/vulns.jsonl"

while IFS= read -r file; do
  gzip -cd "$file" | jq -c '.vulnerabilities[]' >> "$vulns_file"
done < <(find "$feeds_dir" -name "*.json.gz" | sort -V)

total=$(wc -l < "$vulns_file")
log "Total vulnerabilities: $total"

first_feed=$(find "$feeds_dir" -name "*.json.gz" | sort -V | head -1)
format=$(gzip -cd "$first_feed" | jq -r '.format')
version=$(gzip -cd "$first_feed" | jq -r '.version')
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000")

dir=$(begin_output "nvd")

{
  echo "{"
  echo "  \"resultsPerPage\": $total,"
  echo "  \"startIndex\": 0,"
  echo "  \"totalResults\": $total,"
  echo "  \"format\": \"$format\","
  echo "  \"version\": \"$version\","
  echo "  \"timestamp\": \"$timestamp\","
  echo "  \"vulnerabilities\": ["
  awk '{if (NR > 1) print ","; printf "%s", $0}' "$vulns_file"
  echo ""
  echo "  ]"
  echo "}"
} | gzip > "$dir/nvd.json.gz"

log "Created nvd.json.gz ($(du -h "$dir/nvd.json.gz" | awk '{print $1}'))"

verify_vuls_coverage "$FIXTURES_ROOT/nvd" "$dir/nvd.json.gz"
finish_output "nvd"
