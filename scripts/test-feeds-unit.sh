#!/usr/bin/env bash
# Unit test for individual vulsource feed scripts
# Tests that each script produces valid output files
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)

trap 'rm -rf "$TEST_ROOT"' EXIT

# Available feeds
AVAILABLE_FEEDS=(
  "amazon"
  "app-manual"
  "chainguard"
  "debian"
  "github"
  "golang"
  "k8s"
  "mariner-vulnerability"
  "nvd"
  "photon"
  "redhat"
  "suse"
  "ubuntu"
)

# Parse command line options
FEEDS=()
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --all)
      FEEDS=("${AVAILABLE_FEEDS[@]}")
      shift
      ;;
    --help|-h)
      SHOW_HELP=true
      shift
      ;;
    *)
      FEEDS+=("$1")
      shift
      ;;
  esac
done

# Show help if requested
if [[ "$SHOW_HELP" == "true" ]]; then
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [FEEDS...]

Test individual vulsource feed scripts.

Options:
  --all        Test all available feeds
  --help, -h   Show this help message

Available feeds:
$(printf "  - %s\n" "${AVAILABLE_FEEDS[@]}")

Examples:
  # Test default feeds (chainguard, golang, k8s)
  $(basename "$0")

  # Test all feeds
  $(basename "$0") --all

  # Test specific feeds
  $(basename "$0") golang k8s

  # Test a single feed
  $(basename "$0") chainguard
EOF
  exit 0
fi

# Use default set if no feeds specified
if [ ${#FEEDS[@]} -eq 0 ]; then
  FEEDS=(
    "chainguard"
    "golang"
    "k8s"
  )
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

fail() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}

assert_file_exists() {
  local path=$1
  [ -f "$path" ] || fail "File not found: $path"
}

assert_file_nonempty() {
  local path=$1
  [ -s "$path" ] || fail "File is empty: $path"
}

assert_valid_gzip() {
  local path=$1
  gzip -t "$path" 2>/dev/null || fail "Invalid gzip file: $path"
}

assert_valid_tar_gz() {
  local path=$1
  tar -tzf "$path" >/dev/null 2>&1 || fail "Invalid tar.gz file: $path"
}

assert_valid_zip() {
  local path=$1
  unzip -t "$path" >/dev/null 2>&1 || fail "Invalid zip file: $path"
}

assert_tar_contains() {
  local archive=$1
  local path=$2
  tar -tzf "$archive" 2>/dev/null | grep -Fxq "$path" || fail "tar.gz missing: $path"
}

assert_tar_has_files() {
  local archive=$1
  local count
  count=$(tar -tzf "$archive" 2>/dev/null | grep -v '/$' | wc -l)
  [ "$count" -gt 0 ] || fail "tar.gz contains no files"
}

assert_zip_contains() {
  local archive=$1
  local pattern=$2
  unzip -l "$archive" 2>/dev/null | grep -E -q "$pattern" || fail "zip missing pattern: $pattern"
}

# Feed-specific validators
validate_chainguard() {
  local output=$1

  # Should be .zip (changed from tar.gz)
  [[ "$output" == *.zip ]] || fail "chainguard output should be .zip, got: $output"
  assert_valid_zip "$output"

  # Should contain CGA-*.json files
  local json_count
  json_count=$(unzip -l "$output" 2>/dev/null | grep -c "CGA-[a-z0-9].*\.json" || true)
  [ "$json_count" -gt 0 ] || fail "osv-v2.zip contains no CGA-*.json files"

  log "  ✓ chainguard produces valid .zip with $json_count advisories"
}

validate_golang() {
  local output=$1

  # Should be .zip
  [[ "$output" == *.zip ]] || fail "golang output should be .zip, got: $output"
  assert_valid_zip "$output"

  # Should contain GO-*.json files
  local json_count
  json_count=$(unzip -l "$output" 2>/dev/null | grep -c "GO-[0-9].*\.json" || true)
  [ "$json_count" -gt 0 ] || fail "golang-osv.zip contains no GO-*.json files"

  log "  ✓ golang produces valid .zip with $json_count advisories"
}

validate_k8s() {
  local output=$1

  # Should be tar.gz
  assert_valid_tar_gz "$output"

  # Should contain k8s.json.gz
  assert_tar_contains "$output" "k8s/k8s.json.gz"

  log "  ✓ k8s produces valid tar.gz with k8s.json.gz"
}

validate_amazon() {
  local output=$1

  assert_valid_tar_gz "$output"
  assert_tar_contains "$output" "amazon/alas.rss"
  assert_tar_contains "$output" "amazon/alas2.rss"
  assert_tar_contains "$output" "amazon/alas2022.rss"
  assert_tar_contains "$output" "amazon/alas2023.rss"

  log "  ✓ amazon produces valid tar.gz with RSS feeds"
}

validate_app_manual() {
  local output=$1

  assert_valid_tar_gz "$output"
  assert_tar_has_files "$output"

  log "  ✓ app-manual produces valid tar.gz"
}

validate_debian() {
  local output=$1

  assert_valid_tar_gz "$output"
  assert_tar_contains "$output" "debian/debian.json"

  log "  ✓ debian produces valid tar.gz"
}

validate_mariner() {
  local output=$1

  assert_valid_tar_gz "$output"
  assert_tar_contains "$output" "mariner-vulnerability/cbl-mariner-2.0-oval.xml"
  assert_tar_contains "$output" "mariner-vulnerability/osv/"

  log "  ✓ mariner produces valid tar.gz"
}

validate_photon() {
  local output=$1

  assert_valid_tar_gz "$output"
  assert_tar_has_files "$output"

  log "  ✓ photon produces valid tar.gz"
}

validate_redhat() {
  local output=$1

  assert_valid_tar_gz "$output"
  assert_tar_has_files "$output"

  log "  ✓ redhat produces valid tar.gz"
}

validate_suse() {
  local output=$1

  assert_valid_tar_gz "$output"
  assert_tar_has_files "$output"

  log "  ✓ suse produces valid tar.gz"
}

validate_ubuntu() {
  local output=$1

  assert_valid_tar_gz "$output"
  assert_tar_contains "$output" "ubuntu-cve-tracker/active/"
  assert_tar_contains "$output" "ubuntu-cve-tracker/retired/"

  log "  ✓ ubuntu produces valid tar.gz"
}

validate_nvd() {
  local output=$1

  assert_valid_tar_gz "$output"
  assert_tar_has_files "$output"

  log "  ✓ nvd produces valid tar.gz"
}

validate_github() {
  local output=$1

  assert_valid_tar_gz "$output"
  assert_tar_has_files "$output"

  log "  ✓ github produces valid tar.gz"
}

# Run a single feed test (returns 0 on success, 1 on failure)
test_feed() {
  local feed=$1
  local script="$REPO_ROOT/scripts/vulsource/${feed}.sh"
  local script="$REPO_ROOT/scripts/vulsource/${feed}.sh"
  local workdir="$TEST_ROOT/$feed"
  local output_file="$workdir/github_output.txt"
  local log_file="$workdir/run.log"

  log "Testing $feed..."

  # Check script exists
  if [ ! -f "$script" ]; then
    warn "  Script not found: $script (skipping)"
    return 0
  fi

  [ -x "$script" ] || fail "  Script not executable: $script"

  mkdir -p "$workdir"

  # Run the script
  if ! (
    cd "$REPO_ROOT"
    GITHUB_OUTPUT="$output_file" \
    GITHUB_WORKSPACE="$REPO_ROOT" \
    VULSOURCE_VERIFY=1 \
    bash "$script"
  ) >"$log_file" 2>&1; then
    echo ""
    cat "$log_file"
    fail "  $feed script failed"
  fi

  # Extract output_path
  local output_path
  output_path=$(sed -n 's/^output_path=//p' "$output_file" | tail -n 1)

  if [ -z "$output_path" ]; then
    echo ""
    cat "$log_file"
    cat "$output_file"
    fail "  $feed did not emit output_path"
  fi

  # Handle relative paths
  if [[ "$output_path" != /* ]]; then
    output_path="$REPO_ROOT/$output_path"
  fi

  # Validate output file
  assert_file_exists "$output_path"
  assert_file_nonempty "$output_path"

  # Feed-specific validation
  if type "validate_${feed//-/_}" &>/dev/null; then
    "validate_${feed//-/_}" "$output_path"
  else
    warn "  No validator for $feed, only checked file exists"
  fi

  # Show file size
  local size
  size=$(du -h "$output_path" | cut -f1)
  log "  Output: $(basename "$output_path") ($size)"

  return 0
}

# Main execution
main() {
  local failed=0
  local passed=0
  local skipped=0

  log "Running unit tests for vulsource feeds"
  log "Test directory: $TEST_ROOT"
  echo ""

  local feed
  for feed in "${FEEDS[@]}"; do
    if test_feed "$feed"; then
      ((passed++))
    else
      ((failed++))
    fi
    echo ""
  done

  echo "========================================"
  log "Test Summary:"
  log "  Passed:  $passed"
  log "  Failed:  $failed"
  log "  Skipped: $skipped"
  echo ""

  if [ "$failed" -gt 0 ]; then
    fail "Some tests failed"
  fi

  log "${GREEN}All tests passed!${NC}"
}

main "$@"
