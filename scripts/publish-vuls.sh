#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

TARGET_FILE="${TARGET_FILE:-$REPO_ROOT/vul-dbgen/cvedb.regular}"
CHECKSUM_FILE="${CHECKSUM_FILE:-${TARGET_FILE}.sha256}"
REF_FILE="${REF_FILE:-$REPO_ROOT/vul.oci-ref}"
ARTIFACT_TYPE="${ARTIFACT_TYPE:-application/vnd.neuvector.vuldb.v1}"
FILE_MEDIA_TYPE="${FILE_MEDIA_TYPE:-application/octet-stream}"
LOG_PREFIX="${LOG_PREFIX:-publish-vuls}"
OCI_TAG="${OCI_TAG:-${VULN_VER:-latest}}"

if [ -z "${OCI_REPOSITORY:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
    OCI_REPOSITORY="ghcr.io/${GITHUB_REPOSITORY}/vul"
fi

log() {
    echo "[$LOG_PREFIX] $*"
}

if [ -z "${OCI_REPOSITORY:-}" ]; then
    echo "[$LOG_PREFIX] OCI_REPOSITORY is required" >&2
    exit 1
fi

if [ ! -f "$TARGET_FILE" ]; then
    echo "[$LOG_PREFIX] TARGET_FILE not found: $TARGET_FILE" >&2
    exit 1
fi

mkdir -p "$(dirname "$CHECKSUM_FILE")" "$(dirname "$REF_FILE")"

sha256sum "$TARGET_FILE" > "$CHECKSUM_FILE"

OCI_REFERENCE="${OCI_REPOSITORY}:${OCI_TAG}"

log "target=$TARGET_FILE"
log "checksum=$CHECKSUM_FILE"
log "repository=$OCI_REFERENCE"

# Create temporary directory for build context
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

cp "$TARGET_FILE" "$CHECKSUM_FILE" "$temp_dir/"

# Create Dockerfile
cat > "$temp_dir/Dockerfile" <<EOF
FROM scratch
COPY . /feed/
LABEL org.opencontainers.image.title="Vulnerability Database"
LABEL vul.artifact.type="$ARTIFACT_TYPE"
EOF

log "Building and pushing to $OCI_REFERENCE"

# Build and push using docker buildx
docker buildx build \
    --platform linux/amd64 \
    --tag "$OCI_REFERENCE" \
    --push \
    --quiet \
    "$temp_dir" > /dev/null

# Get digest using crane
log "Getting digest..."
digest=$(crane digest "$OCI_REFERENCE")

printf '%s@%s\n' "$OCI_REFERENCE" "$digest" > "$REF_FILE"

log "ref=$(cat "$REF_FILE")"
log "digest=$digest"
