#!/usr/bin/env bash
# Legacy reference: scripts/jenkins-ssh-script-vulsource.sh, section "Update: debian".
# Upstream reference: https://security-tracker.debian.org/tracker/data/json
# Local hotfixes are maintained under scripts/vulsource/hotfixes/debian/.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

HOTFIX_FILES=(
  "debian-buster.json"   # Debian 10 hotfix (NVSHAS-9181)
  "debian-stretch.json"  # Debian 9 hotfix
)

FEED="debian"
DEBIAN_DIR="${HOTFIX_ROOT}/debian"
dir=$(begin_output "$FEED")

echo "Fetching Debian Security Tracker data..."
wget --no-check-certificate -O "$dir/debian.json" \
  https://security-tracker.debian.org/tracker/data/json

# Include hotfix files from release repo if they exist
if [ -d "$DEBIAN_DIR" ]; then
  for hotfix in "${HOTFIX_FILES[@]}"; do
    if [ -f "${DEBIAN_DIR}/${hotfix}" ]; then
      echo "Including hotfix: $hotfix"
      cp "${DEBIAN_DIR}/${hotfix}" "$dir/${hotfix}"
    fi
  done
fi

verify_no_empty_files "$dir"
verify_manifest "$FIXTURES_ROOT/$FEED" "$dir"
finish_output "$FEED"
