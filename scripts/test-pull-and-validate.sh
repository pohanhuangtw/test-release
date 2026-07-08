#!/usr/bin/env bash
# Test pull-vulsource-feeds.sh and validate the result
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

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

error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

# Configuration
PULL_SCRIPT="${PULL_SCRIPT:-$REPO_ROOT/pull.sh}"
VUL_SOURCE_DIR="${VUL_SOURCE_DIR:-$REPO_ROOT/vul-source}"
BACKUP_DIR="${BACKUP_DIR:-$REPO_ROOT/vul-source.backup.$(date +%Y%m%d-%H%M%S)}"
CLEAN_BEFORE_PULL="${CLEAN_BEFORE_PULL:-true}"
VALIDATE_AFTER_PULL="${VALIDATE_AFTER_PULL:-true}"

main() {
  log "Testing pull and validation workflow"
  log "Pull script: $PULL_SCRIPT"
  log "Target directory: $VUL_SOURCE_DIR"
  echo ""

  # Check prerequisites
  if [ ! -f "$PULL_SCRIPT" ]; then
    error "Pull script not found: $PULL_SCRIPT"
    exit 1
  fi

  if ! command -v crane &> /dev/null; then
    error "crane is required but not installed"
    echo "Install: go install github.com/google/go-containerregistry/cmd/crane@latest"
    exit 1
  fi

  # Backup existing vul-source if it exists
  if [ -d "$VUL_SOURCE_DIR" ]; then
    if [[ "$CLEAN_BEFORE_PULL" == "true" ]]; then
      log "Backing up existing vul-source to: $BACKUP_DIR"
      mv "$VUL_SOURCE_DIR" "$BACKUP_DIR"
      log "Old vul-source backed up"
    else
      warn "vul-source already exists, will pull into existing directory"
    fi
  fi
  echo ""

  # Run pull script
  log "Step 1: Running pull script..."
  if ! bash "$PULL_SCRIPT"; then
    error "Pull script failed"
    if [ -d "$BACKUP_DIR" ]; then
      warn "Restoring backup..."
      rm -rf "$VUL_SOURCE_DIR"
      mv "$BACKUP_DIR" "$VUL_SOURCE_DIR"
    fi
    exit 1
  fi
  echo ""

  # Check vul-source was created
  if [ ! -d "$VUL_SOURCE_DIR" ]; then
    error "vul-source directory was not created"
    exit 1
  fi

  # Show pulled structure
  log "Step 2: Pulled structure:"
  if command -v tree &> /dev/null; then
    tree -L 2 -d "$VUL_SOURCE_DIR" || find "$VUL_SOURCE_DIR" -type d | head -50
  else
    find "$VUL_SOURCE_DIR" -type d | head -50
  fi
  echo ""

  # Validate structure
  if [[ "$VALIDATE_AFTER_PULL" == "true" ]]; then
    log "Step 3: Validating structure..."
    if ! "$SCRIPT_DIR/validate-structure.sh"; then
      error "Structure validation failed"
      echo ""
      warn "You can manually inspect: $VUL_SOURCE_DIR"
      warn "Backup is available at: $BACKUP_DIR"
      exit 1
    fi
    echo ""
  fi

  # Generate snapshot
  log "Step 4: Generating structure snapshot..."
  GENERATE_SNAPSHOT=true "$SCRIPT_DIR/validate-structure.sh" || true
  echo ""

  # Success
  log "${GREEN}Pull and validation completed successfully!${NC}"
  echo ""
  log "Results:"
  log "  vul-source: $VUL_SOURCE_DIR"
  if [ -d "$BACKUP_DIR" ]; then
    log "  Backup: $BACKUP_DIR"
    echo ""
    warn "Clean up backup when ready:"
    echo "  rm -rf $BACKUP_DIR"
  fi
  echo ""

  # Show disk usage
  log "Disk usage:"
  du -sh "$VUL_SOURCE_DIR"/* 2>/dev/null | sort -h || true
}

# Command line options
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-clean)
      CLEAN_BEFORE_PULL=false
      shift
      ;;
    --no-validate)
      VALIDATE_AFTER_PULL=false
      shift
      ;;
    --pull-script)
      PULL_SCRIPT="$2"
      shift 2
      ;;
    --vul-source)
      VUL_SOURCE_DIR="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Test pull-vulsource-feeds.sh and validate the result"
      echo ""
      echo "Options:"
      echo "  --no-clean         Don't clean vul-source before pull (pull into existing)"
      echo "  --no-validate      Skip structure validation after pull"
      echo "  --pull-script FILE Use custom pull script (default: ../pull.sh)"
      echo "  --vul-source DIR   Use custom target directory (default: ../vul-source)"
      echo "  --help             Show this help"
      echo ""
      echo "Environment variables:"
      echo "  PULL_SCRIPT        Path to pull script"
      echo "  VUL_SOURCE_DIR     Target directory for pulled feeds"
      echo "  CLEAN_BEFORE_PULL  Clean before pull (true/false)"
      echo "  VALIDATE_AFTER_PULL Validate after pull (true/false)"
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      exit 1
      ;;
  esac
done

main "$@"
