# Vulsource Feed Scripts

This directory contains the feed generators used by CI and local testing.

## Script Contract

Each feed script is expected to:

1. Source [`_lib.sh`](./_lib.sh).
2. Create output in `stage/<feed>` via `begin_output`.
3. Optionally run fixture verification.
4. Finalize with `finish_output "<feed>"`.

Minimal pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

FEED="example"
dir=$(begin_output "$FEED")

# Write files into "$dir"

verify_manifest "$FIXTURES_ROOT/$FEED" "$dir"
verify_vuls_coverage "$FIXTURES_ROOT/$FEED" "$dir/output.json.gz"
finish_output "$FEED"
```

`finish_output` moves `stage/<feed>` to `<feed>` and emits `output_path` to `GITHUB_OUTPUT`. The GitHub action at `.github/actions/run-feed-to-ghcr` depends on that output.

## Staging Rules

- Always write intermediate files under `stage/`.
- `begin_output "$FEED"` creates `stage/<feed>`.
- `finish_output "$FEED"` must use the exact same feed name.
- Avoid trailing spaces in feed names. `finish_output "$FEED "` will look for `stage/<feed> ` and fail.

## Fixture Verification

Fixtures live under `scripts/fixtures/<feed>/`.

Supported checks in [`_lib.sh`](./_lib.sh):

- `verify_manifest "$fixture_dir" "$actual_dir"`
  Verifies the generated file list matches `manifest.txt`.
- `verify_vuls_coverage "$fixture_dir" "$target_path"`
  Verifies the generated vulnerability list is a superset of `content/list.txt` by executing `content/gen.sh`.

Expected fixture layout:

```text
scripts/fixtures/<feed>/
├── manifest.txt
└── content/
    ├── gen.sh
    └── list.txt
```

`manifest.txt` is the expected file list relative to the feed output directory.

`content/gen.sh` should print generated IDs, one per line. When `verify_vuls_coverage` passes a target path, it is available as `VERIFY_TARGET_PATH`.

Not all feeds use fixture verification today.
- `ubuntu` and `mariner` clone the repo directly.
- `k8s` downloads a single file from a fixed URL.

Red Hat has one extra caveat:
- `scripts/fixtures/redhat/manifest.txt` should track files that actually exist in the Red Hat OVAL index.
- Do not assume every `openshift-4.x.oval.xml.bz2` minor release exists.
- For example, current `RHEL8` and `RHEL9` indexes include `openshift-4.22.oval.xml.bz2`, but not `openshift-4.23` through `openshift-4.30`.

## Local Debugging

Run a single feed script:

```bash
GHSA_TOKEN=... GITHUB_OUTPUT=/tmp/feed.out bash scripts/vulsource/github.sh
cat /tmp/feed.out
```

Inspect the generated archive:

```bash
tar -tzf github.tar.gz
```

Run unit tests:

```bash
./scripts/test-feeds-unit.sh github
```
