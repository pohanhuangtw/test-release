# Vulsource Structure Fixtures

This directory contains fixtures for validating the structure of pulled vulsource feeds.

## Purpose

After running `pull.sh`, the vul-source directory should have a specific structure. These fixtures ensure:

1. ✅ All expected directories exist
2. ✅ All expected files exist
3. ✅ Preserved feeds (golang, k8s, chainguard) are NOT extracted
4. ✅ Extracted feeds have correct structure
5. ✅ No unexpected files/directories

## Files

### `expected-structure.txt`

Defines the expected directory structure after pulling feeds.

**Format:**
```
path [type] [note]
```

- `path`: Relative path from vul-source/ (use `*` for wildcards)
- `type`: `D` (directory), `F` (file), `L` (symlink), `*` (any)
- `note`: Optional flags:
  - `optional` - Path may not exist (no error)
  - `preserved` - File should NOT be extracted
  - `multiple` - Expect multiple files matching pattern

**Examples:**
```
apps/ D
apps/golang-osv.zip F preserved
amazon/alas.rss F
debian/*.json * optional
mariner-vulnerability/osv/*.json * multiple
```

### `actual-structure.txt` (generated)

Snapshot of actual structure after running validation with `--snapshot` flag.

## Usage

### Basic Validation

```bash
# Validate current vul-source directory
./scripts/validate-structure.sh
```

### Custom Paths

```bash
# Validate custom directory
./scripts/validate-structure.sh --vul-source /path/to/vul-source

# Use custom fixture
./scripts/validate-structure.sh --fixture /path/to/custom-fixture.txt
```

### Generate Snapshot

```bash
# Validate and generate snapshot
./scripts/validate-structure.sh --snapshot

# Only generate snapshot (no validation)
./scripts/validate-structure.sh --snapshot-only actual-structure.txt
```

### Integrated Test

```bash
# Pull feeds and validate in one step
./scripts/test-pull-and-validate.sh

# Pull without cleaning first
./scripts/test-pull-and-validate.sh --no-clean

# Pull without validation
./scripts/test-pull-and-validate.sh --no-validate
```

## Example Workflows

### 1. Fresh Pull and Validate

```bash
# Clean pull and validate
./scripts/test-pull-and-validate.sh

# Output:
# [INFO] Backing up existing vul-source...
# [INFO] Running pull script...
# [INFO] Validating structure...
#   Passed:   45
#   Failed:   0
#   Warnings: 2
#   Skipped:  5 (optional)
# [INFO] Pull and validation completed successfully!
```

### 2. Update Fixture After Changes

```bash
# 1. Pull feeds
bash pull.sh

# 2. Generate snapshot of actual structure
./scripts/validate-structure.sh --snapshot-only actual-structure.txt

# 3. Review differences
diff -u scripts/fixtures/expected-structure.txt scripts/fixtures/actual-structure.txt

# 4. Update expected structure if changes are correct
cp scripts/fixtures/actual-structure.txt scripts/fixtures/expected-structure.txt
```

### 3. CI/CD Integration

```yaml
# .github/workflows/test-pull.yaml
name: Test Pull Vulsource

on:
  schedule:
    - cron: '0 3 * * *'  # Daily at 3 AM
  workflow_dispatch:

jobs:
  test-pull:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install crane
        uses: ./.github/actions/install-crane

      - name: Pull and validate
        run: ./scripts/test-pull-and-validate.sh

      - name: Upload structure snapshot
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: actual-structure
          path: scripts/fixtures/actual-structure.txt
```

## Validation Rules

### Preserved Feeds (MUST NOT be extracted)

These feeds should exist as archives, with no extracted files:

| Feed | Archive Location | Should NOT contain |
|------|------------------|-------------------|
| golang | `apps/golang-osv.zip` | `GO-*.json` files |
| k8s | `apps/k8s.json.gz` | `k8s.json` file |
| chainguard | `chainguard/osv-v2.tar.gz` | `CGA-*.json` files |

### Extracted Feeds (SHOULD be extracted)

These feeds should be extracted directories:

| Feed | Location | Should contain |
|------|----------|----------------|
| amazon | `amazon/` | `alas*.rss` files |
| debian | `debian/` | `debian*.json` files |
| ubuntu | `ubuntu/ubuntu-cve-tracker/` | `active/`, `retired/` dirs |
| mariner | `mariner-vulnerability/` | `osv/*.json` files |

## Common Issues

### Validation fails: "Missing: apps/golang-osv.zip"

**Problem:** golang feed was extracted instead of preserved.

**Solution:** Check that `golang` is in the exemption list in `pull.sh`:
```bash
case "$feed" in
  k8s|golang|chainguard)
    echo "    Skipping archive extraction for $feed"
    return 0
    ;;
esac
```

### Validation warns: "Unexpected item: foo/"

**Problem:** Extra directory not in expected structure.

**Solutions:**
1. If expected, add to `expected-structure.txt`:
   ```
   foo/ D optional
   ```
2. If not expected, investigate and remove

### Validation fails: "Preserved feed was incorrectly extracted"

**Problem:** Archive exists but files are also extracted.

**Example:**
```
apps/golang-osv.zip    ← Archive exists ✓
apps/GO-2020-0001.json ← Should NOT exist ✗
apps/GO-2020-0002.json ← Should NOT exist ✗
```

**Solution:** Check `pull.sh` `extract_archives` function is correctly exempting the feed.

## Updating Fixtures

When adding a new feed:

1. **Add expected paths to fixture:**
   ```bash
   # Edit scripts/fixtures/expected-structure.txt
   vim scripts/fixtures/expected-structure.txt

   # Add:
   newfeed/ D
   newfeed/data.json F
   newfeed/*.xml * optional
   ```

2. **Test the new feed:**
   ```bash
   # Pull and validate
   ./scripts/test-pull-and-validate.sh
   ```

3. **Review validation results:**
   ```bash
   # Check for unexpected items or missing paths
   # Fix either the feed script or the fixture
   ```

## Reference Structure

Based on `/suse/vuldb/vul-dbgen` reference:

```
vul-source/
├── amazon/
├── app-manual/
├── apps/
│   ├── golang-osv.zip      (preserved)
│   └── k8s.json.gz         (preserved)
├── chainguard/
│   └── osv-v2.tar.gz       (preserved)
├── debian/
├── github/
├── mariner-vulnerability/
│   ├── mariner-vulnerability/
│   └── osv/
├── nvd/
├── photon/
├── redhat/
│   ├── 7/
│   ├── 8/
│   └── 9/
├── suse/
└── ubuntu/
    └── ubuntu-cve-tracker/
        ├── active/
        ├── retired/
        ├── scripts/
        └── test/
```

## Troubleshooting

### "vul-source directory not found"

Pull feeds first:
```bash
bash pull.sh
```

### "Fixture file not found"

Check fixture file exists:
```bash
ls -l scripts/fixtures/expected-structure.txt
```

### Validation passes but structure looks wrong

Generate snapshot and compare:
```bash
./scripts/validate-structure.sh --snapshot
diff scripts/fixtures/expected-structure.txt scripts/fixtures/actual-structure.txt
```
