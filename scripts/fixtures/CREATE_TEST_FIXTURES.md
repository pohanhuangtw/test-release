# Creating Test Fixtures for Vulsource Feeds

## Purpose

Create **fixed snapshots** of vulnerability data for testing, so tests don't depend on:
- Network availability
- Upstream data changes
- Download speed

## Benefits

✅ **Stable tests** - Same input, same output
✅ **Fast tests** - No network downloads
✅ **Offline tests** - Work without internet
✅ **Reproducible** - Anyone can run tests anywhere

## Directory Structure

```
scripts/fixtures/test-data/
├── amazon/
│   ├── alas.rss          (snapshot from 2026-06-30)
│   ├── alas2.rss
│   ├── alas2022.rss
│   └── alas2023.rss
├── chainguard/
│   ├── CGA-sample-1.json
│   ├── CGA-sample-2.json
│   └── index.json        (10 sample advisories)
├── golang/
│   ├── GO-2020-0001.json
│   ├── GO-2020-0002.json
│   └── ...               (10 sample advisories)
└── k8s/
    └── k8s.json          (sample data)
```

## How to Create Fixtures

### 1. Download Current Data

```bash
# Run scripts once to get real data
bash scripts/vulsource/amazon.sh
bash scripts/vulsource/chainguard.sh
bash scripts/vulsource/golang.sh

# Extract to fixtures
mkdir -p scripts/fixtures/test-data/{amazon,chainguard,golang}
```

### 2. Amazon - Copy RSS Files

```bash
cp stage/amazon/*.rss scripts/fixtures/test-data/amazon/
```

### 3. Chainguard - Sample 10 Advisories

```bash
# Extract 10 samples from zip
unzip stage/chainguard/osv-v2.zip -d /tmp/cg-all
cp /tmp/cg-all/CGA-*.json scripts/fixtures/test-data/chainguard/ | head -10
```

### 4. Golang - Sample 10 Advisories

```bash
# Extract 10 samples from zip
unzip golang-osv.zip -d /tmp/go-all
cp /tmp/go-all/GO-2020-*.json scripts/fixtures/test-data/golang/ | head -10
```

### 5. Add README

```bash
cat > scripts/fixtures/test-data/README.md <<EOF
# Test Data Fixtures

**Snapshot Date:** 2026-06-30

These are **fixed snapshots** for testing. They are NOT updated automatically.

## When to Update

- When feed format changes
- When tests need new scenarios
- Once per quarter (not every day!)

## DO NOT

- Update fixtures on every PR
- Expect fixtures to have latest CVEs
- Use fixtures in production

## Purpose

Stable, reproducible test data that doesn't depend on network or upstream changes.
EOF
```

## Using Fixtures in Tests

### Option A: Environment Variable

```bash
# scripts/test-feeds-unit.sh

if [[ "${USE_TEST_FIXTURES:-false}" == "true" ]]; then
  # Use fixed test data
  export AMAZON_TEST_DATA="$SCRIPT_DIR/fixtures/test-data/amazon"
else
  # Use real downloads (current behavior)
  # ...
fi
```

### Option B: Separate Test Script

```bash
# scripts/test-feeds-offline.sh
# Uses only fixture data, no network

for feed in amazon chainguard golang; do
  test_feed_from_fixture "$feed"
done
```

## Example: Modified amazon.sh for Testing

```bash
#!/usr/bin/env bash
# amazon.sh with test fixture support

if [[ -n "${AMAZON_TEST_DATA:-}" ]]; then
  # Use test fixtures (no download)
  dir=$(begin_output "amazon")
  cp "$AMAZON_TEST_DATA"/*.rss "$dir/"
else
  # Real download (current behavior)
  for file in "${!feeds[@]}"; do
    wget --no-check-certificate -O "$dir/$file" "${feeds[$file]}"
  done
fi

finish_output "amazon"
```

## Running Tests

```bash
# Fast offline tests with fixtures
USE_TEST_FIXTURES=true ./scripts/test-feeds-unit.sh

# Full integration tests with real downloads
./scripts/test-feeds-unit.sh

# Both
./scripts/test-feeds-unit.sh --offline   # uses fixtures
./scripts/test-feeds-unit.sh --online    # real downloads
```

## Maintenance

### When to Update Fixtures

✅ Feed format changes
✅ Need new test scenarios
✅ Quarterly refresh

❌ NOT on every PR
❌ NOT to get latest CVEs

### How to Update

```bash
# 1. Download fresh data
bash scripts/vulsource/amazon.sh

# 2. Update fixtures
./scripts/update-test-fixtures.sh amazon

# 3. Commit
git add scripts/fixtures/test-data/
git commit -m "chore: update test fixtures (2026-Q3)"
```
