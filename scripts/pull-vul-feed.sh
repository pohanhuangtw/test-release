#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-ghcr.io/pohanhuang/vul}"
TAG="${TAG:-latest}"
OUTPUT_DIR="${OUTPUT_DIR:-vul-source}"
REF_DIR="${REF_DIR:-.github/vul-refs}"
DEBUG="${DEBUG:-false}"

FEEDS=(
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
  "ubuntu-cve-tracker"
)

# Check if crane is available
check_dependencies() {
  if ! command -v crane &>/dev/null; then
    echo "ERROR: crane is required but not installed."
    echo "Install: go install github.com/google/go-containerregistry/cmd/crane@latest"
    exit 1
  fi
}

# Get reference from .ref file
get_ref_from_file() {
  local feed_name=$1
  local ref_file="${REF_DIR}/${feed_name}.ref"

  if [ -f "$ref_file" ]; then
    cat "$ref_file" | tr -d '\n' || echo ""
  else
    echo ""
  fi
}

# Get expected digest from .ref file
get_expected_digest() {
  local feed_name=$1
  local ref_from_file=$(get_ref_from_file "$feed_name")

  if [ -n "$ref_from_file" ]; then
    # Extract digest from reference (format: repo@sha256:xxx)
    echo "$ref_from_file" | grep -oP 'sha256:[a-f0-9]{64}' || echo ""
  else
    echo ""
  fi
}

# Verify downloaded image digest
verify_digest() {
  local ref=$1
  local expected_digest=$2

  if [ -z "$expected_digest" ]; then
    echo "    ⚠ No reference file found, skipping verification"
    return 0
  fi

  local actual_digest=$(crane digest "$ref" 2>/dev/null || echo "")

  if [ -z "$actual_digest" ]; then 
    echo "    ✗ Failed to get digest from registry"
    return 1
  fi

  if [ "$actual_digest" = "$expected_digest" ]; then
    echo "    ✓ Digest verified: ${actual_digest:0:19}..."
    return 0
  else
    echo "    ✗ Digest mismatch!"
    echo "      Expected: $expected_digest"
    echo "      Got:      $actual_digest"
    return 1
  fi
}

# Pull and extract a single feed
pull_feed() {
  local feed=$1
  local ref="${REPO}/${feed}:${TAG}"
  local feed_dir="${feed%.ref}"
  local output_path="$OUTPUT_DIR/$feed_dir"

  echo "==> Pulling $feed -> $feed_dir"

  # Verify digest
  local expected_digest=$(get_expected_digest "$feed")
  if ! verify_digest "$ref" "$expected_digest"; then
    echo "    ⚠ Continuing despite verification failure..."
  fi

  # Use crane to export the image filesystem
  local temp_tar=$(mktemp)
  trap "rm -f '$temp_tar'" RETURN

  # Try pulling with :latest tag first
  if ! crane export "$ref" "$temp_tar" 2>/dev/null; then
    echo "    ✗ Failed to export $ref"

    # Fallback to digest from .ref file
    local ref_from_file=$(get_ref_from_file "$feed")
    if [ -n "$ref_from_file" ]; then
      echo "    → Falling back to ref file: $ref_from_file"
      ref="$ref_from_file"

      if ! crane export "$ref" "$temp_tar" 2>/dev/null; then
        echo "    ✗ Fallback also failed"
        return 1
      fi
      echo "    ✓ Fallback succeeded"
    else
      echo "    ✗ No .ref file available for fallback"
      return 1
    fi
  fi

  # Extract to output directory
  mkdir -p "$output_path"
  tar -xf "$temp_tar" -C "$output_path" --strip-components=1 feed/ 2>/dev/null ||
    tar -xf "$temp_tar" -C "$output_path" 2>/dev/null

  rm -f "$temp_tar"

  # Auto-extract any .tar.gz files in the feed directory
  extract_archives "$feed" "$output_path"

  # Flatten nested subdirectories (do this AFTER extract_archives)
  case "$feed" in
  k8s | golang | chainguard)
    # Keep these as-is (already flat or need special structure)
    ;;
  *)
    # For other feeds, flatten if there's a duplicate subdirectory
    if [ -d "$output_path/$feed" ]; then
      echo "    Flattening $feed/$feed/ -> $feed/"
      mv "$output_path/$feed"/* "$output_path/" 2>/dev/null || true
      rmdir "$output_path/$feed" 2>/dev/null || true
    fi
    ;;
  esac

  # Remove Dockerfile and .sha256 (metadata files)
  rm -f "$output_path/Dockerfile" "$output_path"/*.sha256

  ls -lh "$output_path" | grep -v '\.zip.*' | awk '{print " " $5 " " $9}'
  # List extracted files
  list_files "$output_path"

  echo ""
  return 0
}

# Extract compressed archives
extract_archives() {
  local feed=$1
  local dir=$2

  case "$feed" in
  k8s | golang | chainguard)
    echo "    Skipping archive extraction for $feed"
    return 0
    ;;
  esac

  for tarball in "$dir"/*.tar.gz; do
    if [ -f "$tarball" ]; then
      echo "    Extracting $(basename "$tarball")..."
      tar -xzf "$tarball" -C "$dir"
      rm "$tarball"
    fi
  done

  for zipfile in "$dir"/*.zip; do
    if [ -f "$zipfile" ]; then
      echo "    Extracting $(basename "$zipfile")..."
      unzip -q "$zipfile" -d "$dir"
      rm "$zipfile"
    fi
  done
}

# List extracted files
list_files() {
  local dir=$1

  echo "    Final structure:"
  if [ "$(ls -A "$dir" 2>/dev/null)" ]; then
    local total_files
    total_files=$(find "$dir" -type f | wc -l | tr -d ' ')

    if [ "$total_files" -eq 0 ]; then
      echo "    ERROR: No files extracted"
      return 1
    fi

    echo "    Total files: $total_files"

    if [ "$DEBUG" = "true" ]; then
      find "$dir" -type f | sort | while read -r file; do
        local size
        size=$(du -h "$file" | awk '{print $1}')
        echo "    - ${file#$dir/} ($size)"
      done
    fi
  else
    echo "    ERROR: No files extracted"
    return 1
  fi
}

# Move app-specific feeds to apps directory
organize_apps() {
  echo "==> Organizing app feeds"
  mkdir -p "$OUTPUT_DIR/apps"

  if [ -f "$OUTPUT_DIR/k8s/k8s.json.gz" ]; then
    echo "    Moving k8s.json.gz to apps/"
    mv "$OUTPUT_DIR/k8s/k8s.json.gz" "$OUTPUT_DIR/apps/"
  fi

  if [ -f "$OUTPUT_DIR/golang/golang-osv.zip" ]; then
    echo "    Moving golang-osv.zip to apps/"
    mv "$OUTPUT_DIR/golang/golang-osv.zip" "$OUTPUT_DIR/apps/"
  fi

  # Clean up empty directories
  # rm -rf "$OUTPUT_DIR/k8s" "$OUTPUT_DIR/golang"
}

# Main execution
main() {
  check_dependencies

  echo "Pulling vulsource feeds from $REPO"
  echo "Output directory: $OUTPUT_DIR"
  echo "Reference directory: $REF_DIR"
  echo ""

  mkdir -p "$OUTPUT_DIR"

  local failed=0
  local total=${#FEEDS[@]}

  for feed in "${FEEDS[@]}"; do
    if ! pull_feed "$feed"; then
      echo "    ✗ Failed to pull $feed" >&2
      failed=$((failed + 1))
    fi
  done

  organize_apps

  echo ""
  echo "==> Summary"
  echo "    Total: $total"
  echo "    Success: $((total - failed))"
  echo "    Failed: $failed"
  echo ""
  echo "All feeds downloaded to $OUTPUT_DIR/"

  if [ $failed -gt 0 ]; then
    exit 1
  fi
}

main "$@"
