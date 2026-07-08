#!/usr/bin/env bash
# Extracted from scripts/jenkins-ssh-script-vulsource.sh.
# Source data is maintained locally under scripts/vulsource/hotfixes/app-manual/.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

HOTFIX="${HOTFIX_ROOT}/app-manual"
echo "Using hotfix directory: $HOTFIX"

FEED="app-manual"
dir=$(begin_output "$FEED")

# Copy all .db files from hotfixes
if [ -d "$HOTFIX" ]; then
  for db in "$HOTFIX"/*.db; do
    if [ -f "$db" ]; then
      filename=$(basename "$db")
      echo "Including $filename"
      cp "$db" "$dir/$filename"
    fi
  done
else
  echo "No app-manual hotfixes found"
  exit 1
fi

verify_no_empty_files "$dir"
verify_manifest "$FIXTURES_ROOT/$FEED" "$dir"
finish_output "$FEED" 
