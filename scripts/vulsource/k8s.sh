#!/usr/bin/env bash
# Legacy reference: scripts/jenkins-ssh-script-vulsource.sh, section "Update: apps".
# Upstream reference: https://kubernetes.io/docs/reference/issues-security/official-cve-feed/index.json
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

FEED="k8s"
dir=$(begin_output "$FEED")

wget --no-check-certificate -O "$dir/k8s.json" \
  https://kubernetes.io/docs/reference/issues-security/official-cve-feed/index.json

output_file="k8s.json.gz"
( cd "$dir" && gzip -c k8s.json > "../$output_file" )

if [ ! -s "$STAGE_DIR/$output_file" ]; then
  echo "Failed to create archive" >&2
  exit 1
fi

verify_no_empty_files "$dir"
finish_output "$output_file"
