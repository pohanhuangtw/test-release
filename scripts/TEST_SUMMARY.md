# Test Summary for Vulsource Feeds

## 📋 Quick Start

```bash
# Test a single feed (unit test)
./scripts/test-feeds-unit.sh golang

# Test multiple feeds
./scripts/test-feeds-unit.sh chainguard golang k8s

# Run end-to-end test (simulates full pipeline)
./scripts/test-feeds-e2e.sh

# Pull feeds and validate structure (full integration test)
./scripts/test-pull-and-validate.sh

# Validate existing vul-source directory
./scripts/validate-structure.sh
```

## ✅ What Gets Tested

### Unit Tests (`test-feeds-unit.sh`)
- ✅ Script runs without errors
- ✅ Produces `output_path` in GITHUB_OUTPUT
- ✅ Output file exists and non-empty
- ✅ Correct file format (.zip, .tar.gz, .gz)
- ✅ Archive structure matches expectations

### E2E Tests (`test-feeds-e2e.sh`)
- ✅ Complete pipeline: script → container → pull → final structure
- ✅ Preserved feeds are NOT auto-extracted
- ✅ App feeds moved to `apps/` directory
- ✅ Final directory structure matches expected layout

### Structure Validation (`validate-structure.sh`)
- ✅ All expected directories exist
- ✅ All expected files exist
- ✅ Preserved feeds are NOT extracted (golang, k8s, chainguard)
- ✅ No unexpected files/directories
- ✅ Correct file types (directory vs file)

### Integration Test (`test-pull-and-validate.sh`)
- ✅ Pull from registry
- ✅ Validate complete structure against fixture
- ✅ Generate structure snapshot
- ✅ Backup existing data before pull

## 📊 Test Results

### Current Feed Status

| Feed | Unit Test | E2E Test | Notes |
|------|-----------|----------|-------|
| ✅ chainguard | PASS | PASS | Preserved as tar.gz |
| ✅ golang | PASS | PASS | Preserved as .zip in apps/ |
| ✅ k8s | PASS | PASS | Preserved as .gz in apps/ |
| ⚠️ amazon | Ready | Pending | Needs e2e validator |
| ⚠️ debian | Ready | Pending | Needs e2e validator |
| ⚠️ mariner | Ready | Pending | Needs e2e validator |
| ⚠️ ubuntu | Ready | Pending | Needs e2e validator |

## 🎯 Expected Outputs

### golang
```
Type: .zip (preserved)
Location: vul-source/apps/golang-osv.zip
Size: ~2.9M
Contents: 3786 GO-*.json files
Auto-extract: NO (preserved in apps/)
```

### k8s
```
Type: .json.gz (preserved)
Location: vul-source/apps/k8s.json.gz
Size: ~53K
Contents: Single JSON file
Auto-extract: NO (preserved in apps/)
```

### chainguard
```
Type: .tar.gz (preserved)
Location: vul-source/chainguard/osv-v2.tar.gz
Size: ~1.7K
Contents: OSV v2 advisories
Auto-extract: NO (feed exempted)
```

### amazon
```
Type: .tar.gz → extracted
Location: vul-source/amazon/
Contents: 
  - alas.rss
  - alas2.rss
  - alas2022.rss
  - alas2023.rss
Auto-extract: YES
```

## 🔧 Running Tests Locally

### Prerequisites
```bash
# Required tools
command -v bash
command -v tar
command -v gzip
command -v zip
command -v unzip
command -v tree  # optional, for pretty output
```

### Unit Test Example
```bash
$ ./scripts/test-feeds-unit.sh golang

[INFO] Running unit tests for vulsource feeds
[INFO] Test directory: /tmp/tmp.ABC123

[INFO] Testing golang...
  ✓ golang produces valid .zip with 3786 advisories
  Output: golang-osv.zip (2.9M)

========================================
[INFO] Test Summary:
  Passed:  1
  Failed:  0
  Skipped: 0

[INFO] All tests passed!
```

### E2E Test Example
```bash
$ ./scripts/test-feeds-e2e.sh

[INFO] Starting end-to-end vulsource feed test
[INFO] Test directory: /tmp/tmp.XYZ789

[INFO] Step 1: Running feed scripts...
  Running chainguard.sh...
  ✓ chainguard -> osv-v2.tar.gz
  Running golang.sh...
  ✓ golang -> golang-osv.zip
  Running k8s.sh...
  ✓ k8s -> k8s.json.gz

[INFO] Step 2: Simulating container structure...
  ✓ chainguard container structure created
  ✓ golang container structure created
  ✓ k8s container structure created

[INFO] Step 3: Simulating pull behavior...
  ✓ chainguard - Skipping archive extraction (preserved feed)
  ✓ golang - Skipping archive extraction (preserved feed)
  ✓ k8s - Skipping archive extraction (preserved feed)

[INFO] Step 4: Organizing app feeds...
  Moving k8s.json.gz to apps/
  Moving golang-osv.zip to apps/

[INFO] Step 5: Validating final structure...
  ✓ chainguard structure valid
  ✓ golang structure valid (preserved as .zip)
  ✓ k8s structure valid

[INFO] Step 6: Final structure:
vul-source/
├── apps
│   ├── golang-osv.zip
│   └── k8s.json.gz
└── chainguard
    └── osv-v2.tar.gz

[INFO] All tests passed!
```

## 🐛 Common Issues

### "Script not executable"
```bash
chmod +x scripts/vulsource/*.sh
```

### "Missing output_path"
Your script must call `finish_output`:
```bash
# In your feed script:
merge_file="yourfeed.tar.gz"
# ... create the archive ...
finish_output "$merge_file"
```

### "Invalid tar.gz file"
Check the actual file:
```bash
tar -tzf yourfeed.tar.gz
```

### E2E test shows extracted files instead of preserved archive
Add your feed to the exemption list in `pull.sh`:
```bash
case "$feed" in
  k8s|golang|chainguard|yourfeed)  # Add here
    echo "    Skipping archive extraction for $feed"
    return 0
    ;;
esac
```

## 📝 Adding Tests for New Feeds

### 1. Add unit test validator
Edit `scripts/test-feeds-unit.sh`:
```bash
validate_yourfeed() {
  local output=$1
  assert_valid_tar_gz "$output"
  assert_tar_contains "$output" "yourfeed/data.json"
  log "  ✓ yourfeed produces valid tar.gz"
}
```

### 2. Add e2e test validator
Edit `scripts/test-feeds-e2e.sh`:
```bash
validate_yourfeed() {
  local dir="$PULL_OUTPUT_DIR/yourfeed"
  [ -d "$dir" ] || fail "yourfeed directory not found"
  [ -f "$dir/data.json" ] || fail "yourfeed/data.json not found"
  log "  ✓ yourfeed structure valid"
}
```

### 3. Add to test list
Edit both scripts, add to `FEEDS` array:
```bash
FEEDS=(
  "chainguard"
  "golang"
  "k8s"
  "yourfeed"  # Add here
)
```

## 🚀 CI/CD Integration

See `scripts/TESTING.md` for GitHub Actions workflow examples.

## 📚 Additional Resources

- [TESTING.md](./TESTING.md) - Detailed testing documentation
- [../pull.sh](../pull.sh) - Pull script that extracts feeds
- [../.github/workflows/publish-vulsource-feed.yaml](../.github/workflows/publish-vulsource-feed.yaml) - Production workflow
