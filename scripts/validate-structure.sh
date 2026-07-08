#!/usr/bin/env bash
# Validate vul-source directory structure against expected fixture
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FIXTURE_FILE="${FIXTURE_FILE:-$SCRIPT_DIR/fixtures/expected-structure.txt}"
VUL_SOURCE_DIR="${VUL_SOURCE_DIR:-$SCRIPT_DIR/../vul-source}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

# Statistics
PASSED=0
FAILED=0
WARNINGS=0
SKIPPED=0

# Parse fixture line
parse_fixture_line() {
  local line=$1
  local path type note

  # Skip comments and empty lines
  [[ "$line" =~ ^[[:space:]]*# ]] && return 1
  [[ -z "${line// }" ]] && return 1

  # Parse: path type [note]
  read -r path type note <<< "$line"

  echo "$path|$type|$note"
  return 0
}

# Check path existence and type
check_path() {
  local path=$1
  local expected_type=$2
  local note=$3
  local full_path="$VUL_SOURCE_DIR/$path"

  # Handle wildcards
  if [[ "$path" == *"*"* ]]; then
    check_wildcard_path "$path" "$expected_type" "$note"
    return $?
  fi

  # Check existence
  if [ ! -e "$full_path" ]; then
    if [[ "$note" == "optional" ]]; then
      warn "Optional path not found: $path"
      ((SKIPPED++))
      return 0
    else
      error "Missing: $path"
      ((FAILED++))
      return 1
    fi
  fi

  # Check type
  case "$expected_type" in
    D)
      if [ ! -d "$full_path" ]; then
        error "Expected directory but found file: $path"
        ((FAILED++))
        return 1
      fi
      ;;
    F)
      if [ ! -f "$full_path" ]; then
        error "Expected file but found directory: $path"
        ((FAILED++))
        return 1
      fi
      ;;
    L)
      if [ ! -L "$full_path" ]; then
        error "Expected symlink: $path"
        ((FAILED++))
        return 1
      fi
      ;;
    \*)
      # Any type is acceptable
      ;;
  esac

  # Success
  ((PASSED++))
  return 0
}

# Check wildcard paths
check_wildcard_path() {
  local pattern=$1
  local expected_type=$2
  local note=$3
  local base_dir
  local file_pattern

  # Split pattern into directory and file pattern
  base_dir=$(dirname "$pattern")
  file_pattern=$(basename "$pattern")

  local full_base_dir="$VUL_SOURCE_DIR/$base_dir"

  # Check if base directory exists
  if [ ! -d "$full_base_dir" ]; then
    if [[ "$note" == "optional" ]]; then
      warn "Optional directory not found: $base_dir"
      ((SKIPPED++))
      return 0
    else
      error "Base directory missing: $base_dir"
      ((FAILED++))
      return 1
    fi
  fi

  # Find matching files
  local matches
  matches=$(find "$full_base_dir" -maxdepth 1 -name "$file_pattern" 2>/dev/null | wc -l)

  if [ "$matches" -eq 0 ]; then
    if [[ "$note" == "optional" ]] || [[ "$note" == *"optional"* ]]; then
      warn "No matches for pattern: $pattern"
      ((SKIPPED++))
      return 0
    else
      error "No files match pattern: $pattern"
      ((FAILED++))
      return 1
    fi
  fi

  # At least one match found
  if [[ "$note" == "multiple" ]]; then
    info "Found $matches files matching: $pattern"
  fi

  ((PASSED++))
  return 0
}

# Check for unexpected files/directories
check_unexpected_items() {
  log "Checking for unexpected items..."

  local known_paths=()

  # Read all expected paths from fixture
  while IFS= read -r line; do
    local parsed
    if parsed=$(parse_fixture_line "$line"); then
      IFS='|' read -r path type note <<< "$parsed"
      # Remove wildcards and trailing slashes for comparison
      path="${path%/}"
      path="${path%%\**}"
      known_paths+=("$path")
    fi
  done < "$FIXTURE_FILE"

  # Find all items in vul-source
  local found_unexpected=0

  while IFS= read -r item; do
    # Remove vul-source prefix
    local rel_path="${item#$VUL_SOURCE_DIR/}"

    # Skip if it's in known paths or a subdirectory of known paths
    local is_known=0
    for known in "${known_paths[@]}"; do
      if [[ "$rel_path" == "$known"* ]]; then
        is_known=1
        break
      fi
    done

    if [ "$is_known" -eq 0 ]; then
      warn "Unexpected item: $rel_path"
      ((WARNINGS++))
      found_unexpected=1
    fi
  done < <(find "$VUL_SOURCE_DIR" -mindepth 1 -maxdepth 2 2>/dev/null || true)

  if [ "$found_unexpected" -eq 0 ]; then
    log "No unexpected items found"
  fi
}

# Validate preserved feeds are NOT extracted
validate_preserved_feeds() {
  log "Validating preserved feeds..."

  local preserved_feeds=(
    "apps/golang-osv.zip:GO-*.json"
    "apps/k8s.json.gz:k8s.json"
    "chainguard/osv-v2.zip:CGA-*.json"
  )

  for feed_info in "${preserved_feeds[@]}"; do
    IFS=':' read -r archive_path extracted_pattern <<< "$feed_info"
    local archive="$VUL_SOURCE_DIR/$archive_path"
    local dir=$(dirname "$archive")

    # Check archive exists
    if [ ! -f "$archive" ]; then
      error "Preserved feed missing: $archive_path"
      ((FAILED++))
      continue
    fi

    # Check that files are NOT extracted
    local extracted_count
    extracted_count=$(find "$dir" -name "$extracted_pattern" 2>/dev/null | wc -l)

    if [ "$extracted_count" -gt 0 ]; then
      error "Preserved feed was incorrectly extracted: $archive_path ($extracted_count files found)"
      ((FAILED++))
    else
      info "Preserved feed OK: $archive_path (not extracted)"
      ((PASSED++))
    fi
  done
}

# Generate actual structure snapshot
generate_snapshot() {
  local output_file="${1:-$SCRIPT_DIR/fixtures/actual-structure.txt}"

  log "Generating structure snapshot to: $output_file"

  {
    echo "# Actual vul-source structure snapshot"
    echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""

    # Generate tree-like structure
    find "$VUL_SOURCE_DIR" -type d -o -type f | sort | while read -r path; do
      local rel_path="${path#$VUL_SOURCE_DIR/}"
      [ -z "$rel_path" ] && continue

      if [ -d "$path" ]; then
        echo "$rel_path/ D"
      elif [ -f "$path" ]; then
        local size
        size=$(du -h "$path" | cut -f1)
        echo "$rel_path F $size"
      fi
    done
  } > "$output_file"

  log "Snapshot saved to: $output_file"
}

# Main validation
main() {
  log "Validating vul-source structure"
  log "Fixture: $FIXTURE_FILE"
  log "Target: $VUL_SOURCE_DIR"
  echo ""

  # Check vul-source directory exists
  if [ ! -d "$VUL_SOURCE_DIR" ]; then
    error "vul-source directory not found: $VUL_SOURCE_DIR"
    exit 1
  fi

  # Check fixture file exists
  if [ ! -f "$FIXTURE_FILE" ]; then
    error "Fixture file not found: $FIXTURE_FILE"
    exit 1
  fi

  # Validate each line in fixture
  log "Checking expected paths..."
  while IFS= read -r line; do
    local parsed
    if parsed=$(parse_fixture_line "$line"); then
      IFS='|' read -r path type note <<< "$parsed"
      check_path "$path" "$type" "$note"
    fi
  done < "$FIXTURE_FILE"

  echo ""

  # Check preserved feeds
  validate_preserved_feeds
  echo ""

  # Check for unexpected items
  check_unexpected_items
  echo ""

  # Print summary
  echo "========================================"
  log "Validation Summary:"
  echo "  ${GREEN}Passed:${NC}   $PASSED"
  echo "  ${RED}Failed:${NC}   $FAILED"
  echo "  ${YELLOW}Warnings:${NC} $WARNINGS"
  echo "  ${BLUE}Skipped:${NC}  $SKIPPED (optional)"
  echo ""

  # Generate snapshot if requested
  if [[ "${GENERATE_SNAPSHOT:-false}" == "true" ]]; then
    generate_snapshot
    echo ""
  fi

  # Exit status
  if [ "$FAILED" -gt 0 ]; then
    error "Validation failed with $FAILED errors"
    exit 1
  elif [ "$WARNINGS" -gt 0 ]; then
    warn "Validation passed with $WARNINGS warnings"
    exit 0
  else
    log "${GREEN}Validation passed!${NC}"
    exit 0
  fi
}

# Command line options
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot)
      GENERATE_SNAPSHOT=true
      shift
      ;;
    --snapshot-only)
      generate_snapshot "${2:-$SCRIPT_DIR/fixtures/actual-structure.txt}"
      exit 0
      ;;
    --fixture)
      FIXTURE_FILE="$2"
      shift 2
      ;;
    --vul-source)
      VUL_SOURCE_DIR="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --snapshot           Generate actual structure snapshot after validation"
      echo "  --snapshot-only FILE Generate snapshot and exit (no validation)"
      echo "  --fixture FILE       Use custom fixture file (default: fixtures/expected-structure.txt)"
      echo "  --vul-source DIR     Validate custom directory (default: ../vul-source)"
      echo "  --help               Show this help"
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      exit 1
      ;;
  esac
done

main "$@"
