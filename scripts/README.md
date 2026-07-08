# Vulsource Scripts

Scripts for managing vulsource vulnerability feeds.

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| [TEST_SUMMARY.md](TEST_SUMMARY.md) | Quick testing guide (start here) |
| [TESTING.md](TESTING.md) | Detailed testing documentation |
| [FIXTURE_SYSTEM.md](FIXTURE_SYSTEM.md) | Structure validation system |
| [vulsource/README.md](vulsource/README.md) | Feed script contract and authoring notes |
| [fixtures/README.md](fixtures/README.md) | Fixture format and usage |

## 🚀 Quick Commands

```bash
# Test a single feed
./scripts/test-feeds-unit.sh golang

# Test multiple feeds
./scripts/test-feeds-unit.sh chainguard golang k8s

# End-to-end test (simulates full pipeline)
./scripts/test-feeds-e2e.sh

# Pull and validate structure
./scripts/test-pull-and-validate.sh

# Validate existing structure
./scripts/validate-structure.sh
```

## 📁 Directory Structure

```
scripts/
├── vulsource/                  Feed generation scripts
│   ├── _lib.sh                    Common functions
│   ├── amazon.sh                  Amazon Linux feeds
│   ├── chainguard.sh              Chainguard feeds
│   ├── golang.sh                  Go vulnerability DB
│   ├── k8s.sh                     Kubernetes advisories
│   └── ...                        Other feeds
│
├── fixtures/                   Structure validation fixtures
│   ├── README.md                  Fixture documentation
│   └── expected-structure.txt     Expected directory structure
│
├── test-feeds-unit.sh          Unit tests for feed scripts
├── test-feeds-e2e.sh           End-to-end pipeline tests
├── validate-structure.sh       Structure validation
├── test-pull-and-validate.sh   Integration test
│
└── Documentation
    ├── README.md                  This file
    ├── TEST_SUMMARY.md            Quick testing guide
    ├── TESTING.md                 Detailed testing docs
    └── FIXTURE_SYSTEM.md          Validation system docs
```

## 🔄 Typical Workflow

### Developing a New Feed

1. **Create feed script:**
   ```bash
   cp scripts/vulsource/template.sh scripts/vulsource/newfeed.sh
   vim scripts/vulsource/newfeed.sh
   ```

2. **Test the script:**
   ```bash
   ./scripts/test-feeds-unit.sh newfeed
   ```

3. **Add to expected structure:**
   ```bash
   vim scripts/fixtures/expected-structure.txt
   # Add:
   # newfeed/ D
   # newfeed/data.json F
   ```

4. **Test full pipeline:**
   ```bash
   ./scripts/test-feeds-e2e.sh
   ```

5. **Commit:**
   ```bash
   git add scripts/vulsource/newfeed.sh
   git add scripts/fixtures/expected-structure.txt
   git commit -m "feat: add newfeed vulsource"
   ```

### Updating an Existing Feed

1. **Modify feed script:**
   ```bash
   vim scripts/vulsource/golang.sh
   ```

2. **Test changes:**
   ```bash
   ./scripts/test-feeds-unit.sh golang
   ```

3. **Pull and validate:**
   ```bash
   ./scripts/test-pull-and-validate.sh
   ```

4. **If structure changed, update fixture:**
   ```bash
   ./scripts/validate-structure.sh --snapshot
   # Review changes
   diff scripts/fixtures/expected-structure.txt scripts/fixtures/actual-structure.txt
   # Update if correct
   cp scripts/fixtures/actual-structure.txt scripts/fixtures/expected-structure.txt
   ```

### Debugging Pull Issues

1. **Check script output:**
   ```bash
   GITHUB_OUTPUT=/tmp/test.out bash scripts/vulsource/golang.sh
   cat /tmp/test.out
   ```

2. **Verify archive contents:**
   ```bash
   tar -tzf golang-osv.tar.gz
   # or
   unzip -l golang-osv.zip
   ```

3. **Test pull in isolation:**
   ```bash
   rm -rf vul-source/
   bash pull.sh
   ```

4. **Validate structure:**
   ```bash
   ./scripts/validate-structure.sh --snapshot
   tree -L 3 vul-source/
   ```

## 🎯 Test Levels

### Level 1: Unit Tests (Fast)

Tests individual feed scripts in isolation.

```bash
./scripts/test-feeds-unit.sh golang
```

**Validates:**
- Script runs without errors
- Produces valid output file
- Archive has correct format and contents

### Level 2: E2E Tests (Medium)

Simulates full pipeline without actual registry.

```bash
./scripts/test-feeds-e2e.sh
```

**Validates:**
- Script → container → pull → structure
- Preserved feeds stay compressed
- Apps organized correctly

### Level 3: Integration Tests (Slow)

Real pull from registry with full validation.

```bash
./scripts/test-pull-and-validate.sh
```

**Validates:**
- Actual registry pull
- Complete structure validation
- No regressions

## 🔍 Key Validation Points

### Preserved Feeds

These must NOT be extracted:

| Feed | Location | Format |
|------|----------|--------|
| golang | `apps/golang-osv.zip` | ZIP with GO-*.json |
| k8s | `apps/k8s.json.gz` | Gzipped JSON |
| chainguard | `chainguard/osv-v2.tar.gz` | Tar.gz with CGA-*.json |

**Validation:**
```bash
# Archives should exist
ls -lh apps/golang-osv.zip
ls -lh apps/k8s.json.gz
ls -lh chainguard/osv-v2.tar.gz

# Files should NOT be extracted
! find apps/ -name "GO-*.json"
! find apps/ -name "k8s.json"
! find chainguard/ -name "CGA-*.json"
```

### Extracted Feeds

These must be extracted:

| Feed | Location | Contents |
|------|----------|----------|
| amazon | `amazon/` | alas*.rss files |
| debian | `debian/` | debian*.json files |
| ubuntu | `ubuntu/ubuntu-cve-tracker/` | Directories: active/, retired/, etc. |

## 🐛 Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| "golang-osv.zip not found" | Not uploaded to registry | Re-run golang.sh and upload |
| "GO-*.json files in apps/" | Feed was extracted | Add to exemption in pull.sh |
| "Missing: amazon/alas.rss" | Feed not extracted | Remove from exemption in pull.sh |
| "Unexpected item: foo/" | New directory | Add to expected-structure.txt |

## 📞 Getting Help

1. **Check documentation:**
   - [TEST_SUMMARY.md](TEST_SUMMARY.md) - Quick start
   - [TESTING.md](TESTING.md) - Detailed guide
   - [FIXTURE_SYSTEM.md](FIXTURE_SYSTEM.md) - Validation system

2. **Run diagnostics:**
   ```bash
   # Generate structure snapshot
   ./scripts/validate-structure.sh --snapshot

   # Compare with expected
   diff scripts/fixtures/expected-structure.txt scripts/fixtures/actual-structure.txt
   ```

3. **Check feed output:**
   ```bash
   GITHUB_OUTPUT=/tmp/out.txt bash scripts/vulsource/yourfeed.sh
   cat /tmp/out.txt
   ```

## 🔗 Related Files

- [../pull.sh](../pull.sh) - Pull feeds from registry
- [../.github/workflows/publish-vulsource-feed.yaml](../.github/workflows/publish-vulsource-feed.yaml) - CI/CD pipeline
- [../.github/actions/run-feed-to-ghcr/action.yml](../.github/actions/run-feed-to-ghcr/action.yml) - Publish action
