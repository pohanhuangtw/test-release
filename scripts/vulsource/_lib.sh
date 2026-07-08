#!/usr/bin/env bash
set -uo pipefail

STAGE_DIR="stage"
REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HOTFIX_ROOT="${REPO_ROOT}/scripts/vulsource/hotfixes"
FIXTURES_ROOT="${REPO_ROOT}/scripts/fixtures/"

# Auto-cleanup stage directory on exit
trap 'rm -rf "$STAGE_DIR"' EXIT

write_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  fi
}

# Setup output directory in staging area
# Returns: path to the staging directory
# Usage: dir=$(begin_output "amazon")
begin_output() {
  local name="$1"
  local stage_path="${STAGE_DIR}/${name}"
  mkdir -p "$stage_path"
  echo "$stage_path"
}

# Finalize output: move from stage to final location and emit
# Usage: finish_output "amazon"
finish_output() {
  local name="$1"
  local stage_path="${STAGE_DIR}/${name}"

  if [ ! -e "$stage_path" ]; then
    echo "Stage path not found: $stage_path" >&2
    return 1
  fi

  mkdir -p "$(dirname "$name")"
  mv "$stage_path" "$name"
  emit_output_path "$name"
}

emit_output_path() {
  local path="$1"

  if [ -f "$path" ]; then
    # File: accept .gz, .tar.gz, or .zip, otherwise compress it
    case "$path" in
      *.tar.gz|*.tgz|*.gz|*.zip)
        # Already compressed
        write_output output_path "$path"
        ;;
      *.tar|*.bz2|*.xz)
        # Other compression formats not supported
        echo "Only .gz/.tar.gz/.zip formats supported, got: $path" >&2
        return 1
        ;;
      *)
        # Not compressed, gzip it
        gzip -f "$path"
        write_output output_path "${path}.gz"
        ;;
    esac
  elif [ -d "$path" ]; then
    # Directory: tar.gz the whole directory
    local dir_name
    dir_name="$(basename "$path")"
    local parent_dir
    parent_dir="$(dirname "$path")"
    local tar_file="${path}.tar.gz"

    tar -C "$parent_dir" -czf "$tar_file" "$dir_name"
    write_output output_path "$tar_file"
  else
    echo "Path not found: $path" >&2
    return 1
  fi
}

verify_no_empty_files() {
  local target="$1"
  local empty_list="$STAGE_DIR/empty_files.txt"

  echo "[Verify non-empty files]: $target"

  if [ ! -e "$target" ]; then
    echo "[Verify non-empty files failed]: $target" >&2
    echo "Verification target not found: $target" >&2
    return 1
  fi

  find "$target" -type f -empty | sort > "$empty_list"

  if [ -s "$empty_list" ]; then
    echo "[Verify non-empty files failed]: $target" >&2
    echo "Empty files found:" >&2
    sed 's/^/  /' "$empty_list" >&2
    return 1
  fi

  echo "[Verify non-empty files success]: $target"
}

# Verify the manifest(files) are all in the new feeds
verify_manifest() {
  local fixture="$1"
  local actual="$2"
  local manifest_file="$fixture/manifest.txt"
  local expected_list="$STAGE_DIR/expected_manifest.txt"
  local actual_list="$STAGE_DIR/actual_manifest.txt"

  echo "[Verify manifest]: $manifest_file"

  sed 's/[[:space:]]*$//' "$manifest_file" \
    | sed '/^$/d' \
    | sort -u > "$expected_list"

  (
    cd "$actual"
    find . -type f -printf '%P\n' | sort -u
  ) > "$actual_list"

  diff "$expected_list" "$actual_list" || {
    echo "[Verify manifest failed]: $manifest_file" >&2
    echo "Manifest mismatch" >&2
    return 1
  }

  echo "[Verify manifest success]: $manifest_file"
}

# Ensure that the generated list of vulnerabilities is a superset of the fixture list
verify_vuls_coverage() {
  local fixture="$1"
  local target_path="${2:-}"
  local gen_script="$fixture/content/gen.sh"
  local list_file="$fixture/content/list.txt"

  echo "[Verify vulnerability coverage]: $list_file"

  if [ ! -f "$gen_script" ]; then
    echo "[Verify vulnerability coverage failed]: $gen_script" >&2
    echo "Generation script not found: $gen_script" >&2
    return 1
  fi

  if [ ! -s "$list_file" ]; then
    echo "[Verify vulnerability coverage skipped]: $list_file" >&2
    echo "Fixture list is empty or missing at $list_file, skipping list verification"
    return 0
  fi

  if [ -n "$target_path" ]; then
    VERIFY_TARGET_PATH="$target_path" bash "$gen_script" > "$STAGE_DIR/generated_list.txt"
  else
    bash "$gen_script" > "$STAGE_DIR/generated_list.txt"
  fi

  missing=$(
    comm -23 \
      <(LC_ALL=C sed 's/[[:space:]]*$//' "$list_file" | LC_ALL=C sort -u) \
      <(LC_ALL=C sed 's/[[:space:]]*$//' "$STAGE_DIR/generated_list.txt" | LC_ALL=C sort -u)
  )

  if [ -n "$missing" ]; then
    echo "[Verify vulnerability coverage failed]: $list_file" >&2
    echo "Generated list is not a superset. Missing entries:" >&2
    printf '%s\n' "$missing" >&2
    return 1
  fi

  echo "[Verify vulnerability coverage success]: $list_file"
}
