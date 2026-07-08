#!/usr/bin/env bash
# Legacy reference: scripts/jenkins-ssh-script-vulsource.sh, section "Update: Amazon".
# Upstream references:
# - https://alas.aws.amazon.com/
# - https://alas.aws.amazon.com/alas.rss
# - https://alas.aws.amazon.com/AL2/alas.rss
# - https://alas.aws.amazon.com/AL2022/alas.rss
# - https://alas.aws.amazon.com/AL2023/alas.rss
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

declare -A feeds=(
  ["alas.rss"]="https://alas.aws.amazon.com/alas.rss"
  ["alas2.rss"]="https://alas.aws.amazon.com/AL2/alas.rss"
  ["alas2022.rss"]="https://alas.aws.amazon.com/AL2022/alas.rss"
  ["alas2023.rss"]="https://alas.aws.amazon.com/AL2023/alas.rss"
)

FEED="amazon"
dir=$(begin_output "$FEED")

for file in "${!feeds[@]}"; do
  wget --no-check-certificate -O - "${feeds[$file]}" | gzip > "$dir/$file.gz"
done

verify_no_empty_files "$dir"
verify_manifest "$FIXTURES_ROOT/$FEED" "$dir"
finish_output "$FEED" 