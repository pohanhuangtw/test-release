#!/usr/bin/env bash
# End-to-end test for vulsource feeds
# Tests the complete pipeline: script -> tar.gz -> container -> pull -> final structure
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_ROOT=$(mktemp -d)

trap 'rm -rf "$TEST_ROOT"' EXIT

# Feeds to test
FEEDS=(
  "chainguard"
  "golang"
  "k8s"
  # Add more feeds as needed:
  # "amazon"
  # "app-manual"
  # "debian"
  # "mariner"
  # "ubuntu"
)

REGISTRY_DIR="$TEST_ROOT/registry"
PULL_OUTPUT_DIR="$TEST_ROOT/vul-source"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Step 1: Run feed scripts and collect outputs
run_feed_scripts() {
  log "Step 1: Running feed scripts..."

  local feed
  for feed in "${FEEDS[@]}"; do
    local script="$REPO_ROOT/scripts/vulsource/${feed}.sh"
    local workdir="$TEST_ROOT/feeds/$feed"
    local output_file="$workdir/github_output.txt"
    local log_file="$workdir/run.log"

    [ -x "$script" ] || fail "Script not found or not executable: $script"

    mkdir -p "$workdir"
    log "  Running $feed.sh..."

    if ! (
      cd "$REPO_ROOT"
      GITHUB_OUTPUT="$output_file" \
      GITHUB_WORKSPACE="$REPO_ROOT" \
      bash "$script"
    ) >"$log_file" 2>&1; then
      cat "$log_file" >&2
      fail "Feed script failed: $feed"
    fi

    # Extract output_path
    local output_path
    output_path=$(sed -n 's/^output_path=//p' "$output_file" | tail -n 1)
    [ -n "$output_path" ] || fail "Missing output_path for $feed"

    # Handle relative paths
    if [[ "$output_path" != /* ]]; then
      output_path="$REPO_ROOT/$output_path"
    fi

    [ -f "$output_path" ] || fail "Output file not found: $output_path"

    echo "$output_path" > "$workdir/output_path.txt"
    log "  ✓ $feed -> $(basename "$output_path")"
  done
}

# Step 2: Simulate container structure
simulate_container_structure() {
  log "Step 2: Simulating container structure..."

  local feed
  for feed in "${FEEDS[@]}"; do
    local workdir="$TEST_ROOT/feeds/$feed"
    local output_path
    output_path=$(cat "$workdir/output_path.txt")

    local feed_registry_dir="$REGISTRY_DIR/$feed"
    mkdir -p "$feed_registry_dir/feed"

    # Copy the output file to the simulated container structure
    cp "$output_path" "$feed_registry_dir/feed/"

    # Create a minimal Dockerfile (for reference)
    cat > "$feed_registry_dir/Dockerfile" <<EOF
FROM scratch
COPY . /feed/
EOF

    log "  ✓ $feed container structure created"
  done
}

# Step 3: Simulate pull behavior
simulate_pull() {
  log "Step 3: Simulating pull behavior..."

  mkdir -p "$PULL_OUTPUT_DIR"

  local feed
  for feed in "${FEEDS[@]}"; do
    local feed_registry_dir="$REGISTRY_DIR/$feed"
    local output_path="$PULL_OUTPUT_DIR/$feed"

    mkdir -p "$output_path"

    # Extract files from simulated container
    cp -r "$feed_registry_dir/feed/"* "$output_path/"

    # Simulate extract_archives logic
    case "$feed" in
      k8s|golang|chainguard)
        log "  ✓ $feed - Skipping archive extraction (preserved feed)"
        ;;
      *)
        # Auto-extract .tar.gz files
        local tarball
        for tarball in "$output_path"/*.tar.gz; do
          if [ -f "$tarball" ]; then
            log "  Extracting $(basename "$tarball")..."
            tar -xzf "$tarball" -C "$output_path"
            rm "$tarball"
          fi
        done

        # Auto-extract .zip files
        local zipfile
        for zipfile in "$output_path"/*.zip; do
          if [ -f "$zipfile" ]; then
            log "  Extracting $(basename "$zipfile")..."
            unzip -q "$zipfile" -d "$output_path"
            rm "$zipfile"
          fi
        done
        ;;
    esac

    log "  ✓ $feed extracted to vul-source/$feed/"
  done
}

# Step 4: Organize app feeds
organize_apps() {
  log "Step 4: Organizing app feeds..."

  mkdir -p "$PULL_OUTPUT_DIR/apps"

  # Move k8s.json.gz to apps/
  if [ -f "$PULL_OUTPUT_DIR/k8s/k8s.json.gz" ]; then
    log "  Moving k8s.json.gz to apps/"
    mv "$PULL_OUTPUT_DIR/k8s/k8s.json.gz" "$PULL_OUTPUT_DIR/apps/"
    rmdir "$PULL_OUTPUT_DIR/k8s" 2>/dev/null || true
  fi

  # Move golang-osv.zip to apps/
  if [ -f "$PULL_OUTPUT_DIR/golang/golang-osv.zip" ]; then
    log "  Moving golang-osv.zip to apps/"
    mv "$PULL_OUTPUT_DIR/golang/golang-osv.zip" "$PULL_OUTPUT_DIR/apps/"
    rmdir "$PULL_OUTPUT_DIR/golang" 2>/dev/null || true
  fi
}

# Validation functions
validate_chainguard() {
  local dir="$PULL_OUTPUT_DIR/chainguard"

  [ -d "$dir" ] || fail "chainguard directory not found"

  # Should contain osv-v2.zip (not extracted)
  [ -f "$dir/osv-v2.zip" ] || fail "chainguard/osv-v2.zip not found"

  # Should NOT be extracted
  local json_count
  json_count=$(find "$dir" -name "CGA-*.json" 2>/dev/null | wc -l)
  [ "$json_count" -eq 0 ] || fail "osv-v2.zip was incorrectly extracted ($json_count .json files found)"

  log "  ✓ chainguard structure valid (preserved as .zip)"
}

validate_golang() {
  local apps_dir="$PULL_OUTPUT_DIR/apps"

  [ -d "$apps_dir" ] || fail "apps directory not found"

  # Should be moved to apps/
  [ -f "$apps_dir/golang-osv.zip" ] || fail "apps/golang-osv.zip not found"

  # Should NOT be extracted
  local json_count
  json_count=$(find "$apps_dir" -name "GO-*.json" 2>/dev/null | wc -l)
  [ "$json_count" -eq 0 ] || fail "golang-osv.zip was incorrectly extracted ($json_count .json files found)"

  log "  ✓ golang structure valid (preserved as .zip)"
}

validate_k8s() {
  local apps_dir="$PULL_OUTPUT_DIR/apps"

  [ -d "$apps_dir" ] || fail "apps directory not found"

  # Should be moved to apps/
  [ -f "$apps_dir/k8s.json.gz" ] || fail "apps/k8s.json.gz not found"

  log "  ✓ k8s structure valid"
}

validate_amazon() {
  local dir="$PULL_OUTPUT_DIR/amazon"

  [ -d "$dir" ] || fail "amazon directory not found"
  [ -f "$dir/alas.rss" ] || fail "amazon/alas.rss not found"
  [ -f "$dir/alas2.rss" ] || fail "amazon/alas2.rss not found"
  [ -f "$dir/alas2022.rss" ] || fail "amazon/alas2022.rss not found"
  [ -f "$dir/alas2023.rss" ] || fail "amazon/alas2023.rss not found"

  log "  ✓ amazon structure valid"
}

validate_debian() {
  local dir="$PULL_OUTPUT_DIR/debian"

  [ -d "$dir" ] || fail "debian directory not found"
  [ -f "$dir/debian.json" ] || fail "debian/debian.json not found"

  log "  ✓ debian structure valid"
}

validate_mariner() {
  local dir="$PULL_OUTPUT_DIR/mariner-vulnerability"

  [ -d "$dir" ] || fail "mariner-vulnerability directory not found"
  [ -f "$dir/cbl-mariner-2.0-oval.xml" ] || fail "mariner-vulnerability/cbl-mariner-2.0-oval.xml not found"
  [ -d "$dir/osv" ] || fail "mariner-vulnerability/osv directory not found"

  local osv_count
  osv_count=$(find "$dir/osv" -name "*.json" 2>/dev/null | wc -l)
  [ "$osv_count" -gt 0 ] || fail "mariner-vulnerability/osv/ is empty"

  log "  ✓ mariner structure valid"
}

validate_ubuntu() {
  local dir="$PULL_OUTPUT_DIR/ubuntu-cve-tracker"

  [ -d "$dir" ] || fail "ubuntu-cve-tracker directory not found"
  [ -d "$dir/active" ] || fail "ubuntu-cve-tracker/active directory not found"
  [ -d "$dir/retired" ] || fail "ubuntu-cve-tracker/retired directory not found"

  log "  ✓ ubuntu structure valid"
}

# Step 5: Validate final structure
validate_final_structure() {
  log "Step 5: Validating final structure..."

  local feed
  for feed in "${FEEDS[@]}"; do
    if type "validate_${feed//-/_}" &>/dev/null; then
      "validate_${feed//-/_}"
    else
      warn "No validation function for $feed, skipping"
    fi
  done
}

# Step 6: Print final structure
print_final_structure() {
  log "Step 6: Final structure:"
  echo ""
  tree -L 3 "$PULL_OUTPUT_DIR" 2>/dev/null || find "$PULL_OUTPUT_DIR" -type f -o -type d | sort | sed 's|^|  |'
  echo ""
}

# Main execution
main() {
  log "Starting end-to-end vulsource feed test"
  log "Test directory: $TEST_ROOT"
  echo ""

  run_feed_scripts
  echo ""

  simulate_container_structure
  echo ""

  simulate_pull
  echo ""

  organize_apps
  echo ""

  validate_final_structure
  echo ""

  print_final_structure

  log "${GREEN}All tests passed!${NC}"
  log "Test artifacts preserved at: $TEST_ROOT"
  log "(Will be cleaned up on exit)"
}

main "$@"
