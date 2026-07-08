#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_FILE="$SCRIPT_DIR/list.txt"
TEMP_EXTRACTED="/tmp/extracted_cves_$$.txt"

if [ ! -f "$LIST_FILE" ]; then
    echo "Error: list.txt not found at $LIST_FILE"
    exit 1
fi

echo "Extracting CVE IDs from NVD JSON files..."

# Extract CVE IDs from all JSON files (both .json and .json.gz)
for file in "$SCRIPT_DIR"/vul-source-private/nvd/*.json.gz "$SCRIPT_DIR"/vul-source-private/nvd/*.json; do
    if [ -f "$file" ]; then
        if [[ "$file" == *.gz ]]; then
            gunzip -c "$file" | jq -r '.vulnerabilities[]?.cve.id' 2>/dev/null
        else
            jq -r '.vulnerabilities[]?.cve.id' "$file" 2>/dev/null
        fi
    fi
done | sort -u > "$TEMP_EXTRACTED"

echo "Comparing with list.txt..."

if diff -q "$LIST_FILE" "$TEMP_EXTRACTED" > /dev/null 2>&1; then
    echo "✓ Verification passed: CVE list matches NVD data"
    rm -f "$TEMP_EXTRACTED"
    exit 0
else
    echo "✗ Verification failed: CVE list does not match NVD data"
    echo ""
    echo "Differences:"
    diff "$LIST_FILE" "$TEMP_EXTRACTED" | head -50
    echo ""
    echo "Expected CVEs: $(wc -l < "$LIST_FILE")"
    echo "Extracted CVEs: $(wc -l < "$TEMP_EXTRACTED")"
    rm -f "$TEMP_EXTRACTED"
    exit 1
fi
