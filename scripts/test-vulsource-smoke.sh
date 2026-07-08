#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TMP_ROOT=$(mktemp -d)

trap 'rm -rf "$TMP_ROOT"' EXIT

DEFAULT_TARGETS=(
  "app-manual"
  "amazon"
  "k8s"
  "mariner"
  "ubuntu"
)

if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  TARGETS=("${DEFAULT_TARGETS[@]}")
fi

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

assert_file_nonempty() {
  local path=$1
  [ -s "$path" ] || fail "expected non-empty file: $path"
}

assert_tar_contains() {
  local archive=$1
  local path=$2

  grep -Fxq "$path" < <(tar -tzf "$archive") || fail "expected $path in $(basename "$archive")"
}

assert_tar_subtree_nonempty() {
  local archive=$1
  local prefix=$2

  grep -Eq "^${prefix}.+" < <(tar -tzf "$archive") || fail "expected non-empty subtree ${prefix} in $(basename "$archive")"
}

validate_app_manual() {
  local archive=$1

  assert_tar_contains "$archive" "app-manual/"
  assert_tar_subtree_nonempty "$archive" "app-manual/"
}

validate_amazon() {
  local archive=$1

  assert_tar_contains "$archive" "amazon/"
  assert_tar_contains "$archive" "amazon/alas.rss"
  assert_tar_contains "$archive" "amazon/alas2.rss"
  assert_tar_contains "$archive" "amazon/alas2022.rss"
  assert_tar_contains "$archive" "amazon/alas2023.rss"
}

validate_debian() {
  local archive=$1

  assert_tar_contains "$archive" "debian/"
  assert_tar_contains "$archive" "debian/debian.json"
  assert_tar_contains "$archive" "debian/debian-buster.json"
  assert_tar_contains "$archive" "debian/debian-stretch.json"
  assert_tar_subtree_nonempty "$archive" "debian/"
}

validate_k8s() {
  local archive=$1

  assert_tar_contains "$archive" "k8s/"
  assert_tar_contains "$archive" "k8s/k8s.json.gz"
}

validate_mariner() {
  local archive=$1

  assert_tar_contains "$archive" "mariner-vulnerability/"
  assert_tar_contains "$archive" "mariner-vulnerability/cbl-mariner-2.0-oval.xml"
  assert_tar_contains "$archive" "mariner-vulnerability/osv/"
  assert_tar_subtree_nonempty "$archive" "mariner-vulnerability/osv/"
}

validate_ubuntu() {
  local archive=$1

  assert_tar_contains "$archive" "ubuntu-cve-tracker/"
  assert_tar_contains "$archive" "ubuntu-cve-tracker/active/"
  assert_tar_contains "$archive" "ubuntu-cve-tracker/retired/"
  assert_tar_contains "$archive" "ubuntu-cve-tracker/scripts/"
  assert_tar_contains "$archive" "ubuntu-cve-tracker/test/"
  assert_tar_subtree_nonempty "$archive" "ubuntu-cve-tracker/active/"
  assert_tar_subtree_nonempty "$archive" "ubuntu-cve-tracker/retired/"
  assert_tar_subtree_nonempty "$archive" "ubuntu-cve-tracker/scripts/"
  assert_tar_subtree_nonempty "$archive" "ubuntu-cve-tracker/test/"
}

run_target() {
  local target=$1
  local script="$REPO_ROOT/scripts/vulsource/${target}.sh"
  local workdir="$TMP_ROOT/$target"
  local output_file="$workdir/github_output.txt"
  local log_file="$workdir/run.log"
  local output_path
  local archive

  [ -x "$script" ] || fail "script not found or not executable: $script"

  mkdir -p "$workdir"

  echo "==> Smoke testing $target"
  if ! (
    cd "$workdir"
    GITHUB_OUTPUT="$output_file" \
    GITHUB_WORKSPACE="$REPO_ROOT" \
    "$script"
  ) >"$log_file" 2>&1; then
    cat "$log_file" >&2
    fail "smoke test failed for $target"
  fi

  output_path=$(sed -n 's/^output_path=//p' "$output_file" | tail -n 1)
  [ -n "$output_path" ] || fail "missing output_path for $target"

  archive="$workdir/$output_path"
  assert_file_nonempty "$archive"

  "validate_${target//-/_}" "$archive"

  echo "PASS: $target -> $output_path"
}

main() {
  local target

  for target in "${TARGETS[@]}"; do
    run_target "$target"
  done
}

main "$@"
