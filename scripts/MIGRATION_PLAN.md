# Vulsource Migration Plan

## Goal

Smoothly transition from old vulsource system to new system **without data loss** or service disruption.

## Concerns to Address

### 1. Data Completeness

**Risk:** New system might have fewer vulnerabilities than old system.

**Example:**
```
Old system: 10,000 CVEs
New system: 500 CVEs   ← 95% data loss! ❌
```

**Mitigation:**
- Compare vulnerability counts before/after
- Verify critical CVEs are present
- Run both systems in parallel for validation period

### 2. Format Compatibility

**Risk:** New data format might break downstream consumers.

**Example:**
```json
// Old format
{"cve": "CVE-2024-1234", "severity": "high"}

// New format (incompatible)
{"id": "CVE-2024-1234", "cvss": 7.5}  ← field names changed! ❌
```

**Mitigation:**
- Schema validation
- Backward compatibility checks
- Gradual rollout

### 3. Early Detection

**Risk:** Issues discovered after full rollout are expensive to fix.

**Mitigation:**
- Staged rollout
- Automated validation
- Rollback plan

---

## Migration Phases

### Phase 1: Parallel Running (Week 1-2)

Run both old and new systems side-by-side:

```
┌─────────────┐
│ Old System  │──┐
└─────────────┘  │
                 ├──→ Compare Results
┌─────────────┐  │
│ New System  │──┘
└─────────────┘
```

**Actions:**
1. Deploy new system alongside old
2. Both systems pull/process data
3. Compare outputs daily
4. Fix discrepancies

**Success Criteria:**
- ✅ New system produces ≥95% of old system's data
- ✅ No critical CVEs missing
- ✅ Format compatible with downstream

### Phase 2: Shadow Mode (Week 3)

New system runs but old system is still primary:

```
┌─────────────┐
│ Old System  │──→ Production Database
└─────────────┘

┌─────────────┐
│ New System  │──→ Test Database (not used yet)
└─────────────┘
```

**Actions:**
1. New system writes to test database
2. Monitor for errors/exceptions
3. Performance testing
4. Validate downstream compatibility

**Success Criteria:**
- ✅ Zero errors in new system for 1 week
- ✅ Performance acceptable
- ✅ Downstream tools can read test database

### Phase 3: Gradual Cutover (Week 4)

Incrementally switch traffic:

```
Day 1-2:  10% → New System, 90% → Old System
Day 3-4:  50% → New System, 50% → Old System
Day 5-7: 100% → New System, 0% → Old System
```

**Actions:**
1. Use feature flag to control traffic split
2. Monitor metrics closely
3. Quick rollback if issues

**Success Criteria:**
- ✅ No increase in errors
- ✅ User-facing services unaffected
- ✅ Data quality maintained

### Phase 4: Monitoring (Week 5+)

New system is primary, old system on standby:

```
┌─────────────┐
│ New System  │──→ Production Database ← Primary
└─────────────┘

┌─────────────┐
│ Old System  │ (standby, can rollback quickly)
└─────────────┘
```

**Actions:**
1. Monitor for 1 week
2. Keep old system ready for rollback
3. After 1 week, decommission old system

---

## Validation Scripts

### Script 1: Compare Vulnerability Counts

```bash
#!/usr/bin/env bash
# scripts/compare-old-vs-new.sh

echo "==> Comparing Old vs New System"

# Count vulnerabilities in old system
old_count=$(sqlite3 old-db.sqlite "SELECT COUNT(*) FROM vulnerabilities")

# Count vulnerabilities in new system
new_count=$(sqlite3 new-db.sqlite "SELECT COUNT(*) FROM vulnerabilities")

# Calculate difference
diff=$((new_count - old_count))
pct=$(echo "scale=2; ($diff * 100) / $old_count" | bc)

echo "Old system: $old_count vulnerabilities"
echo "New system: $new_count vulnerabilities"
echo "Difference: $diff ($pct%)"

# Validate
if [[ $diff -lt -500 ]]; then
  echo "❌ FAIL: New system has significantly fewer vulnerabilities!"
  exit 1
elif [[ $diff -lt 0 ]]; then
  echo "⚠️  WARN: New system has fewer vulnerabilities, verify this is expected"
  exit 0
else
  echo "✅ PASS: New system has equal or more vulnerabilities"
  exit 0
fi
```

### Script 2: Verify Critical CVEs

```bash
#!/usr/bin/env bash
# scripts/verify-critical-cves.sh

# List of critical CVEs that MUST be present
CRITICAL_CVES=(
  "CVE-2024-1234"
  "CVE-2024-5678"
  # ... add more
)

echo "==> Verifying Critical CVEs"

missing=0
for cve in "${CRITICAL_CVES[@]}"; do
  if ! sqlite3 new-db.sqlite "SELECT 1 FROM vulnerabilities WHERE cve_id='$cve'" | grep -q 1; then
    echo "❌ Missing: $cve"
    ((missing++))
  else
    echo "✅ Found: $cve"
  fi
done

if [[ $missing -gt 0 ]]; then
  echo "❌ FAIL: $missing critical CVEs missing!"
  exit 1
else
  echo "✅ PASS: All critical CVEs present"
  exit 0
fi
```

### Script 3: Schema Validation

```bash
#!/usr/bin/env bash
# scripts/validate-schema.sh

echo "==> Validating Output Schema"

# Check that new system output has required fields
required_fields=("id" "severity" "description" "published")

for field in "${required_fields[@]}"; do
  if ! jq -e ".[0].$field" vul-source/output.json > /dev/null 2>&1; then
    echo "❌ Missing required field: $field"
    exit 1
  else
    echo "✅ Field present: $field"
  fi
done

echo "✅ PASS: Schema validation successful"
```

---

## Rollback Plan

If issues are discovered:

### Quick Rollback (< 5 minutes)

```bash
# 1. Flip feature flag
echo "VULSOURCE_USE_OLD_SYSTEM=true" >> .env

# 2. Restart services
systemctl restart vul-scanner

# 3. Verify
curl http://localhost/health | jq '.vulsource_system'
# Should show: "old"
```

### Full Rollback (< 30 minutes)

```bash
# 1. Stop new system
systemctl stop vulsource-new

# 2. Restore old database (if needed)
cp /backup/old-db.sqlite /var/lib/vulsource/db.sqlite

# 3. Restart old system
systemctl restart vulsource-old

# 4. Verify data
./scripts/verify-critical-cves.sh
```

---

## Monitoring Checklist

During migration, monitor these metrics:

### System Health
- [ ] Error rate < 0.1%
- [ ] API latency < 500ms p99
- [ ] Memory usage stable
- [ ] No service crashes

### Data Quality
- [ ] Vulnerability count within 5% of old system
- [ ] All critical CVEs present
- [ ] No format errors in output
- [ ] Downstream tools working

### User Impact
- [ ] No user-reported issues
- [ ] Scanner success rate unchanged
- [ ] Report generation working
- [ ] API responses correct

---

## Communication Plan

### Before Migration
- Email to engineering team (1 week before)
- Slack announcement (#security channel)
- Update runbook

### During Migration
- Slack updates every 4 hours
- Incident channel ready
- On-call engineer assigned

### After Migration
- Post-mortem report
- Metrics dashboard
- Lessons learned document

---

## Success Metrics

Migration is successful when:

1. ✅ New system running for 1 week without errors
2. ✅ Vulnerability count ≥ old system
3. ✅ All critical CVEs present
4. ✅ No user-reported issues
5. ✅ Downstream tools compatible
6. ✅ Performance meets SLA

Then: **Decommission old system** ✅
