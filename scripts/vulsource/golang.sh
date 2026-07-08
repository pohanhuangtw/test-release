#!/usr/bin/env bash
# Legacy references:
# - scripts/jenkins-ssh-script-vulsource.sh, function download_golang_osv_data()
# - scripts/jenkins-ssh-script-vulsource.sh, section "Download go OSV advisories"
# Upstream references:
# - https://github.com/golang/vulndb
# - https://github.com/golang/vulndb/tree/master/data/osv
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

echo "Fetching Go OSV data from vulndb repository..."
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/golang/vulndb.git "${STAGE_DIR}/vulndb-osv"

git -C "${STAGE_DIR}/vulndb-osv" sparse-checkout init --cone
git -C "${STAGE_DIR}/vulndb-osv" sparse-checkout set data/osv

file_count=$(find "${STAGE_DIR}/vulndb-osv/data/osv" -name '*.json' 2>/dev/null | wc -l)

if [ "$file_count" -eq 0 ]; then
  echo "No OSV JSON files found" >&2
  exit 1
fi

echo "Found $file_count Go advisories, creating archive..."

# Create tar.gz archive (flat structure) in the staging directory
output_file="golang-osv.zip"
( cd "${STAGE_DIR}/vulndb-osv/data/osv" && zip -r "../../../$output_file" *.json )

if [ ! -s "$STAGE_DIR/$output_file" ]; then
  echo "Failed to create archive" >&2
  exit 1
fi

echo "Successfully created $(du -h "$STAGE_DIR/$output_file" | cut -f1) archive ($file_count advisories)"

rm -rf "${STAGE_DIR}/vulndb-osv"

verify_vuls_coverage "$FIXTURES_ROOT/golang" "$STAGE_DIR/$output_file"
finish_output "$output_file"
