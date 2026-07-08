# Vulsource Feed Testing

This directory contains test scripts for validating vulsource feed generation and distribution.

## Test Scripts

### 1. Unit Tests (`test-feeds-unit.sh`)

Tests individual feed scripts to ensure they produce valid output files.

**Usage:**
```bash
# Test default feeds (chainguard, golang, k8s)
./scripts/test-feeds-unit.sh

# Test specific feeds
./scripts/test-feeds-unit.sh golang k8s chainguard

# Test all available feeds
./scripts/test-feeds-unit.sh amazon app-manual chainguard debian github golang k8s mariner photon redhat suse ubuntu nvd
```

**What it validates:**
- ✅ Script executes without errors
- ✅ Script emits `output_path` to `GITHUB_OUTPUT`
- ✅ Output file exists and is non-empty
- ✅ Output file has correct format (.tar.gz or .zip)
- ✅ Archive contains expected files/structure

**Example output:**
```
[INFO] Testing golang...
  ✓ golang produces valid .zip with 3786 advisories
  Output: golang-osv.zip (2.9M)

[INFO] Testing k8s...
  ✓ k8s produces valid tar.gz with k8s.json.gz
  Output: k8s.json.gz (53K)
```

---

### 2. End-to-End Tests (`test-feeds-e2e.sh`)

Tests the complete pipeline from script execution through container simulation to final directory structure.

**Usage:**
```bash
# Run e2e test for default feeds
./scripts/test-feeds-e2e.sh
```

**What it validates:**
- ✅ Feed scripts produce correct output
- ✅ Container structure is correct
- ✅ Pull behavior extracts files correctly
- ✅ App feeds are moved to `apps/` directory
- ✅ Final directory structure matches expected layout
- ✅ Preserved feeds (golang, k8s, chainguard) are NOT auto-extracted

**Pipeline stages:**
1. **Run feed scripts** → Generate .tar.gz or .zip files
2. **Simulate container** → Copy files to `/feed/` structure
3. **Simulate pull** → Extract from container to `vul-source/`
4. **Organize apps** → Move golang-osv.zip and k8s.json.gz to `apps/`
5. **Validate structure** → Check final directory layout

**Expected final structure:**
```
vul-source/
├── apps/
│   ├── golang-osv.zip     (preserved, not extracted)
│   └── k8s.json.gz        (preserved, not extracted)
├── chainguard/
│   └── osv-v2.tar.gz      (preserved, not extracted)
├── amazon/
│   ├── alas.rss           (extracted from amazon.tar.gz)
│   ├── alas2.rss
│   └── ...
└── ...
```

---

## CI Integration

### GitHub Actions Workflow

Add to `.github/workflows/test-feeds.yaml`:

```yaml
name: Test Vulsource Feeds

on:
  pull_request:
    paths:
      - 'scripts/vulsource/**'
  workflow_dispatch:

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        feed:
          - chainguard
          - golang
          - k8s
    steps:
      - uses: actions/checkout@v4
      - name: Run unit test
        run: ./scripts/test-feeds-unit.sh ${{ matrix.feed }}

  e2e-test:
    runs-on: ubuntu-latest
    needs: unit-tests
    steps:
      - uses: actions/checkout@v4
      - name: Run e2e test
        run: ./scripts/test-feeds-e2e.sh
```

---

## Writing New Validators

### Unit Test Validator

Add a function to `test-feeds-unit.sh`:

```bash
validate_yourfeed() {
  local output=$1

  # Check file format
  assert_valid_tar_gz "$output"

  # Check required files exist in archive
  assert_tar_contains "$output" "yourfeed/data.json"
  assert_tar_contains "$output" "yourfeed/metadata.xml"

  # Check archive has content
  assert_tar_has_files "$output"

  log "  ✓ yourfeed produces valid tar.gz"
}
```

### E2E Test Validator

Add a function to `test-feeds-e2e.sh`:

```bash
validate_yourfeed() {
  local dir="$PULL_OUTPUT_DIR/yourfeed"

  # Check directory exists
  [ -d "$dir" ] || fail "yourfeed directory not found"

  # Check required files
  [ -f "$dir/data.json" ] || fail "yourfeed/data.json not found"
  [ -f "$dir/metadata.xml" ] || fail "yourfeed/metadata.xml not found"

  # Check file count
  local file_count
  file_count=$(find "$dir" -type f | wc -l)
  [ "$file_count" -gt 0 ] || fail "yourfeed directory is empty"

  log "  ✓ yourfeed structure valid ($file_count files)"
}
```

---

## Troubleshooting

### Test fails with "Script not found"

Make sure the feed script exists and is executable:
```bash
ls -l scripts/vulsource/yourfeed.sh
chmod +x scripts/vulsource/yourfeed.sh
```

### Test fails with "Invalid tar.gz"

Check the feed script's output:
```bash
GITHUB_OUTPUT=/tmp/test.out bash scripts/vulsource/yourfeed.sh
cat /tmp/test.out
# Should show: output_path=/path/to/file.tar.gz

# Verify the file
tar -tzf /path/to/file.tar.gz
```

### E2E test fails with "Missing output_path"

The feed script must write to `GITHUB_OUTPUT`:
```bash
# In your feed script:
finish_output "$merge_file"

# This calls emit_output_path which writes:
echo "output_path=$path" >> "$GITHUB_OUTPUT"
```

### Preserved feeds are being extracted

Check that the feed is in the exemption list in `pull.sh`:
```bash
case "$feed" in
  k8s|golang|chainguard)  # Add your feed here
    echo "    Skipping archive extraction for $feed"
    return 0
    ;;
esac
```

---

## Development Workflow

1. **Make changes** to a feed script
2. **Run unit test** to verify output format
   ```bash
   ./scripts/test-feeds-unit.sh yourfeed
   ```
3. **Run e2e test** to verify final structure
   ```bash
   ./scripts/test-feeds-e2e.sh
   ```
4. **Commit** if tests pass
5. **CI runs** both tests on PR

---

## Test Coverage

| Feed | Unit Test | E2E Test | Validator |
|------|-----------|----------|-----------|
| chainguard | ✅ | ✅ | ✅ |
| golang | ✅ | ✅ | ✅ |
| k8s | ✅ | ✅ | ✅ |
| amazon | ✅ | ✅ | ✅ |
| debian | ✅ | ✅ | ✅ |
| mariner | ✅ | ✅ | ✅ |
| ubuntu | ✅ | ✅ | ✅ |
| app-manual | ✅ | ⚠️  | ⚠️ |
| photon | ✅ | ⚠️  | ⚠️ |
| redhat | ✅ | ⚠️  | ⚠️ |
| suse | ✅ | ⚠️  | ⚠️ |
| nvd | ✅ | ⚠️  | ⚠️ |
| github | ✅ | ⚠️  | ⚠️ |

⚠️ = Basic validation only, needs feed-specific checks
