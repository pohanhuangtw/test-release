#!/usr/bin/env bash
# Legacy reference: scripts/jenkins-ssh-script-vulsource.sh, section "Update: Red Hat".
# Upstream references:
# - https://www.redhat.com/security/data/oval/v2/
# - https://access.redhat.com/documentation/en-us/red_hat_security_data_api/
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

download_rh_feed() {
  local out="$1"
  local url="$2"

  if ! curl -fLsk -o "$out" "$url" || [ ! -s "$out" ]; then
    rm -f "$out"
  fi
}

dir=$(begin_output "redhat")
mkdir -p "$dir/7" "$dir/8" "$dir/9"

# RHEL 7
for f in rhel-7.oval.xml.bz2 rhel-7-including-unpatched.oval.xml.bz2 \
         rhsso.oval.xml.bz2 rhsso-including-unpatched.oval.xml.bz2; do
  download_rh_feed "$dir/7/$f" "https://www.redhat.com/security/data/oval/v2/RHEL7/$f"
done

# RHEL 8
for f in rhel-8.oval.xml.bz2 rhel-8-including-unpatched.oval.xml.bz2 \
         rhsso.oval.xml.bz2 rhsso-including-unpatched.oval.xml.bz2 \
         fast-datapath.oval.xml.bz2 fast-datapath-including-unpatched.oval.xml.bz2 \
         openshift-4-including-unpatched.oval.xml.bz2; do
  download_rh_feed "$dir/8/$f" "https://www.redhat.com/security/data/oval/v2/RHEL8/$f"
done

for minor in $(seq 1 30); do
  f="openshift-4.$minor.oval.xml.bz2"
  download_rh_feed "$dir/8/$f" "https://www.redhat.com/security/data/oval/v2/RHEL8/$f"
done

# RHEL 9
for f in rhel-9.oval.xml.bz2 rhel-9-including-unpatched.oval.xml.bz2 \
         rhsso.oval.xml.bz2 rhsso-including-unpatched.oval.xml.bz2 \
         fast-datapath.oval.xml.bz2 fast-datapath-including-unpatched.oval.xml.bz2 \
         openshift-4-including-unpatched.oval.xml.bz2; do
  download_rh_feed "$dir/9/$f" "https://www.redhat.com/security/data/oval/v2/RHEL9/$f"
done

for minor in $(seq 12 30); do
  f="openshift-4.$minor.oval.xml.bz2"
  download_rh_feed "$dir/9/$f" "https://www.redhat.com/security/data/oval/v2/RHEL9/$f"
done

verify_no_empty_files "$dir"
verify_manifest "$FIXTURES_ROOT/redhat" "$dir"
finish_output "redhat"
