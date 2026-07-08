# Vulsource Structure Fixture System

## Overview

A comprehensive fixture-based testing system to ensure `vul-source` directory has the correct structure after pulling feeds from the registry.

## 📁 Files Created

```
scripts/
├── fixtures/
│   ├── README.md                  # Fixture documentation
│   └── expected-structure.txt     # Expected directory structure
├── validate-structure.sh          # Structure validation script
├── test-pull-and-validate.sh      # Integration test script
├── test-feeds-unit.sh             # Unit tests (existing, updated)
├── test-feeds-e2e.sh              # E2E tests (existing)
├── TESTING.md                     # Testing documentation
├── TEST_SUMMARY.md                # Quick reference (updated)
└── FIXTURE_SYSTEM.md              # This file
```

## 🎯 Purpose

Validate that after running `pull.sh` or `pull-vulsource-feeds.sh`, the `vul-source/` directory:

1. ✅ Has all expected directories
2. ✅ Has all expected files
3. ✅ Preserved feeds are NOT extracted (golang, k8s, chainguard)
4. ✅ Extracted feeds have correct structure
5. ✅ No unexpected files/directories

## 🚀 Quick Start

### 1. Validate Current Structure

```bash
./scripts/validate-structure.sh
```

**Output:**
```
[INFO] Validating vul-source structure
[INFO] Checking expected paths...
[INFO] Validating preserved feeds...
  ✓ Preserved feed OK: apps/golang-osv.zip (not extracted)
  ✓ Preserved feed OK: apps/k8s.json.gz (not extracted)
  ✓ Preserved feed OK: chainguard/osv-v2.tar.gz (not extracted)
[INFO] Checking for unexpected items...
[INFO] No unexpected items found
========================================
[INFO] Validation Summary:
  Passed:   45
  Failed:   0
  Warnings: 2
  Skipped:  5 (optional)

[INFO] Validation passed!
```

### 2. Pull and Validate (Full Integration)

```bash
./scripts/test-pull-and-validate.sh
```

**What it does:**
1. Backs up existing `vul-source/`
2. Runs `pull.sh` to download feeds
3. Validates final structure against fixture
4. Generates structure snapshot

### 3. Generate Structure Snapshot

```bash
./scripts/validate-structure.sh --snapshot
```

Creates `scripts/fixtures/actual-structure.txt` showing current structure.

## 📋 Fixture Format

`scripts/fixtures/expected-structure.txt` defines expected structure:

```
# Format: path [type] [note]
# Types: D (directory), F (file), L (symlink), * (any)

# Preserved feeds (NOT extracted)
apps/ D
apps/golang-osv.zip F preserved
apps/k8s.json.gz F preserved

# Extracted feeds
amazon/ D
amazon/alas.rss F
amazon/alas2.rss F

# Wildcards for multiple files
debian/*.json * optional
mariner-vulnerability/osv/*.json * multiple
```

### Fixture Rules

| Type | Meaning | Example |
|------|---------|---------|
| `D` | Directory | `apps/ D` |
| `F` | File | `apps/golang-osv.zip F` |
| `L` | Symlink | `focal -> bionic L` |
| `*` | Any type | `debian/*.json *` |

| Note | Meaning | Effect |
|------|---------|--------|
| `optional` | May not exist | No error if missing |
| `preserved` | Should NOT be extracted | Validates files aren't extracted |
| `multiple` | Expect multiple matches | Info message about count |

## 🔍 Validation Checks

### 1. Path Existence

Checks each path in fixture exists in `vul-source/`.

```bash
# Example fixture line:
amazon/alas.rss F

# Validates:
# - vul-source/amazon/alas.rss exists
# - It's a file (not directory)
```

### 2. Type Matching

Ensures correct type (directory vs file).

```bash
# Fails if:
apps/ D  ← but apps is a file
apps/golang-osv.zip F  ← but golang-osv.zip is a directory
```

### 3. Preserved Feeds

**Critical check:** Ensures preserved feeds are NOT extracted.

```bash
# Checks that apps/golang-osv.zip exists
# AND no GO-*.json files exist in apps/
```

| Feed | Archive | Should NOT Contain |
|------|---------|-------------------|
| golang | `apps/golang-osv.zip` | `GO-*.json` files |
| k8s | `apps/k8s.json.gz` | `k8s.json` file |
| chainguard | `chainguard/osv-v2.tar.gz` | `CGA-*.json` files |

### 4. Unexpected Items

Warns about files/directories not in fixture.

```bash
# If vul-source/ contains:
vul-source/
├── apps/           ← Expected ✓
├── amazon/         ← Expected ✓
└── unknown-feed/   ← Unexpected ⚠

# Output:
[WARN] Unexpected item: unknown-feed/
```

## 🛠️ Common Workflows

### Add New Feed

1. **Pull the new feed:**
   ```bash
   bash pull.sh
   ```

2. **Generate snapshot:**
   ```bash
   ./scripts/validate-structure.sh --snapshot
   ```

3. **Review changes:**
   ```bash
   diff scripts/fixtures/expected-structure.txt scripts/fixtures/actual-structure.txt
   ```

4. **Update fixture:**
   ```bash
   # Add new feed paths to expected-structure.txt
   vim scripts/fixtures/expected-structure.txt

   # Add:
   newfeed/ D
   newfeed/data.json F
   newfeed/*.xml * optional
   ```

5. **Validate:**
   ```bash
   ./scripts/validate-structure.sh
   ```

### Update Expected Structure

After intentional structural changes:

```bash
# 1. Pull feeds
bash pull.sh

# 2. Generate actual structure
./scripts/validate-structure.sh --snapshot-only actual.txt

# 3. Review differences
diff scripts/fixtures/expected-structure.txt actual.txt

# 4. If changes are correct, update fixture
cp actual.txt scripts/fixtures/expected-structure.txt
```

### Debug Structure Issues

```bash
# 1. See what actually exists
tree -L 3 vul-source/

# 2. Generate snapshot
./scripts/validate-structure.sh --snapshot

# 3. Compare with expected
diff -u scripts/fixtures/expected-structure.txt \
        scripts/fixtures/actual-structure.txt

# 4. Check specific feed
ls -lah vul-source/apps/
```

## 🐛 Troubleshooting

### "Missing: apps/golang-osv.zip"

**Problem:** golang feed was extracted instead of preserved.

**Check:**
```bash
ls -lh vul-source/apps/
# Should show:
# golang-osv.zip  2.9M
# NOT:
# GO-2020-0001.json
# GO-2020-0002.json
# ...
```

**Fix:** Ensure `golang` is in exemption list in `pull.sh`:
```bash
case "$feed" in
  k8s|golang|chainguard)
    echo "    Skipping archive extraction for $feed"
    return 0
    ;;
esac
```

### "Preserved feed was incorrectly extracted"

**Problem:** Archive exists but files are also extracted.

**Example:**
```
apps/
├── golang-osv.zip      ← Archive exists ✓
├── GO-2020-0001.json   ← Should NOT exist ✗
└── GO-2020-0002.json   ← Should NOT exist ✗
```

**Fix:**
1. Check `pull.sh` exempts the feed
2. Re-pull without old data:
   ```bash
   rm -rf vul-source/
   bash pull.sh
   ```

### "Unexpected item: foo/"

**Problem:** Extra directory not in expected structure.

**Options:**

1. **If expected, add to fixture:**
   ```bash
   echo "foo/ D optional" >> scripts/fixtures/expected-structure.txt
   ```

2. **If not expected, remove:**
   ```bash
   rm -rf vul-source/foo/
   ```

## 📊 Expected Structure Reference

Based on `/suse/vuldb/vul-dbgen (refactor/build-vuldb-CI)`:

```
vul-source/
├── amazon/
│   ├── alas.rss
│   ├── alas2.rss
│   ├── alas2022.rss
│   └── alas2023.rss
├── app-manual/
│   └── *.json
├── apps/                          (created by organize_apps)
│   ├── golang-osv.zip             (preserved, NOT extracted)
│   └── k8s.json.gz                (preserved, NOT extracted)
├── chainguard/
│   └── osv-v2.tar.gz              (preserved, NOT extracted)
├── debian/
│   └── debian*.json
├── github/
│   └── *.json
├── mariner-vulnerability/
│   ├── cbl-mariner-2.0-oval.xml
│   └── osv/
│       └── *.json
├── nvd/
│   └── *.json
├── photon/
│   └── *.json
├── redhat/
│   ├── 7/
│   ├── 8/
│   └── 9/
├── suse/
│   └── *.xml
└── ubuntu/
    └── ubuntu-cve-tracker/
        ├── active/
        ├── retired/
        ├── scripts/
        └── test/
```

## 🔗 Integration with CI/CD

### GitHub Actions Example

```yaml
name: Validate Vulsource Structure

on:
  schedule:
    - cron: '0 4 * * *'  # Daily at 4 AM
  workflow_dispatch:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install crane
        uses: ./.github/actions/install-crane

      - name: Pull and validate
        run: ./scripts/test-pull-and-validate.sh

      - name: Upload snapshot on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: structure-snapshot
          path: scripts/fixtures/actual-structure.txt

      - name: Compare structures
        if: failure()
        run: |
          echo "Expected vs Actual:"
          diff -u scripts/fixtures/expected-structure.txt \
                  scripts/fixtures/actual-structure.txt || true
```

## 📚 Related Documentation

- [fixtures/README.md](fixtures/README.md) - Detailed fixture documentation
- [TESTING.md](TESTING.md) - Complete testing guide
- [TEST_SUMMARY.md](TEST_SUMMARY.md) - Quick reference
- [../pull.sh](../pull.sh) - Pull script that creates the structure

## ✅ Validation Checklist

Before committing changes to feed scripts:

- [ ] Run unit test: `./scripts/test-feeds-unit.sh <feed>`
- [ ] Pull feeds: `bash pull.sh`
- [ ] Validate structure: `./scripts/validate-structure.sh`
- [ ] Check preserved feeds: Ensure archives exist, no extracted files
- [ ] Generate snapshot: `./scripts/validate-structure.sh --snapshot`
- [ ] Update fixture if needed: Review and update `expected-structure.txt`
- [ ] Re-validate: `./scripts/validate-structure.sh`
- [ ] Commit: Include both code and fixture changes
