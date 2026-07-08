#!/usr/bin/env bash
# Legacy references:
# - scripts/jenkins-ssh-script-vulsource.sh, function fetch_and_process_suse_oval()
# - scripts/jenkins-ssh-script-vulsource.sh, section "Update: SUSE"
# Upstream reference: https://ftp.suse.com/pub/projects/security/oval/
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

oval_entries="
suse.linux.enterprise.server.16.xml.gz
suse.linux.enterprise.server.15.xml.gz
suse.linux.enterprise.server.12.xml.gz
suse.linux.enterprise.server.11.xml.gz
suse.linux.enterprise.server.10.xml.gz
opensuse.leap.16.0.xml.gz
opensuse.leap.15.6.xml.gz
opensuse.leap.15.5.xml.gz
opensuse.leap.15.4.xml.gz
opensuse.leap.15.3.xml.gz
opensuse.leap.15.2.xml.gz
opensuse.leap.15.1.xml.gz
opensuse.leap.15.0.xml.gz
suse.liberty.linux.7.xml.gz
suse.liberty.linux.7-patch.xml.gz
suse.liberty.linux.8.xml.gz
suse.liberty.linux.8-patch.xml.gz
suse.liberty.linux.9.xml.gz
suse.liberty.linux.9-patch.xml.gz
opensuse.tumbleweed.xml.gz
suse.linux.enterprise.micro.5.0.xml.gz
suse.linux.enterprise.micro.5.0-patch.xml.gz
suse.linux.enterprise.micro.5.1.xml.gz
suse.linux.enterprise.micro.5.1-patch.xml.gz
suse.linux.enterprise.micro.5.2.xml.gz
suse.linux.enterprise.micro.5.2-patch.xml.gz
suse.linux.enterprise.micro.5.3.xml.gz
suse.linux.enterprise.micro.5.3-patch.xml.gz
suse.linux.enterprise.micro.5.4.xml.gz
suse.linux.enterprise.micro.5.4-patch.xml.gz
suse.linux.enterprise.micro.5.5.xml.gz
suse.linux.enterprise.micro.5.5-patch.xml.gz
suse.linux.enterprise.micro.5.xml.gz
suse.linux.enterprise.micro.5-patch.xml.gz
suse.linux.enterprise.micro.6.0.xml.gz
suse.linux.enterprise.micro.6.0-patch.xml.gz
suse.linux.enterprise.micro.6.1.xml.gz
suse.linux.enterprise.micro.6.1-patch.xml.gz
"

FEED="suse"
dir=$(begin_output "$FEED")

echo "$oval_entries" | while read -r file; do
  [ -z "$file" ] && continue
  url="https://ftp.suse.com/pub/projects/security/oval/$file"
  if wget --no-check-certificate -O "$dir/$file" "$url" && gzip -t "$dir/$file"; then
    : # downloaded and verified
  else
    echo "Failed to download or verify $file"
  fi
done

verify_no_empty_files "$dir"
verify_manifest "$FIXTURES_ROOT/$FEED" "$dir"
finish_output "$FEED"
