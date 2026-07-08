#!/usr/bin/env bash
# Legacy reference: scripts/jenkins-ssh-script-vulsource.sh, section "Update: Photon".
# Upstream references:
# - https://packages.broadcom.com/photon/photon_cve_metadata/
# - https://packages.broadcom.com/photon/photon_cve_metadata/photon_versions.json
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

FEED="photon"
dir=$(begin_output "$FEED")

base=https://packages.broadcom.com/photon/photon_cve_metadata
curl -sL "$base/photon_versions.json" | jq -r '.branches[]' | while read -r ver; do
  file="cve_data_photon${ver}.json"
  if wget --no-check-certificate -O "$dir/$file" "$base/$file"; then
    gzip "$dir/$file"
    echo "Downloaded and compressed: $file.gz"
  else
    echo "Failed to download: $file" >&2
  fi
done

verify_no_empty_files "$dir"
verify_manifest "$FIXTURES_ROOT/$FEED" "$dir"
finish_output "$FEED"
