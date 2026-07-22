# Cutover Runbook — VxRail Migration

## Runbook Overview

This runbook covers the DNS cutover, validation, and rollback procedures for both phases.

| Phase | Environments | Cutover Type | Risk | Max Rollback Time |
|-------|-------------|-------------|------|-------------------|
| Phase 1 | Dev + QA | Any time (non-prod) | Low | 30 minutes |
| Phase 2 | PreProd | Any time (non-prod) | Medium | 30 minutes |
| Phase 2 | Production | Maintenance window | High | 30 minutes (hard deadline) |

---

## Part 1 — Phase 1 Cutover (Dev + QA)

### Dev Cutover Checklist

```bash
#!/bin/bash
# dev-cutover-checklist.sh

echo "===== DEV CUTOVER CHECKLIST ====="

# 1. On-prem dev app is healthy
echo -n "[1] Dev app health: "
DEV_LB=$(kubectl get svc webapp-svc -n dev -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -sf "http://${DEV_LB}/health" > /dev/null && echo "PASS" || echo "FAIL — do not proceed"

# 2. Dev PostgreSQL connected
echo -n "[2] Dev PostgreSQL: "
psql "host=10.0.5.11 user=dev_user password=DevPostgres2026! dbname=dev_db" \
  -c "SELECT 1;" -t 2>/dev/null | grep -q 1 && echo "PASS" || echo "FAIL"

# 3. Dev MongoDB connected
echo -n "[3] Dev MongoDB: "
mongosh "mongodb://dev_user:DevMongo2026!@10.0.5.21:27017/dev-cosmos?authSource=dev-cosmos" \
  --eval "db.runCommand({ping:1})" --quiet 2>/dev/null | grep -q '"ok": 1' && echo "PASS" || echo "FAIL"

# 4. All dev pods running
echo -n "[4] Dev pods status: "
NOT_RUNNING=$(kubectl get pods -n dev --no-headers | grep -v Running | grep -v Completed | wc -l)
[ "$NOT_RUNNING" -eq 0 ] && echo "PASS" || echo "FAIL ($NOT_RUNNING pods not Running)"

echo ""
echo "If all checks PASS, proceed with DNS cutover."
```

### DNS Cutover Commands

```bash
# Lower TTL 24 hours BEFORE cutover (so DNS change propagates quickly)
# Change TTL on: dev.company.com, qa.company.com to 60 seconds

# At cutover time — update DNS records
# dev.company.com   A → 10.0.4.200  (MetalLB IP for dev namespace)
# qa.company.com    A → 10.0.4.201  (MetalLB IP for qa namespace)

# Verify DNS propagated
nslookup dev.company.com
nslookup qa.company.com

# Monitor for 30 minutes after DNS change
watch -n 10 "curl -s -o /dev/null -w '%{http_code}' http://dev.company.com/health"
```

### Phase 1 Rollback Procedure

Trigger if any check fails within 30 minutes of DNS cutover:

```bash
# 1. Revert DNS to Azure IPs
# dev.company.com  A → <azure-dev-lb-ip>
# qa.company.com   A → <azure-qa-lb-ip>

# 2. Verify Azure apps still reachable
curl -f "http://<azure-dev-lb-ip>/health" && echo "Azure Dev: UP"
curl -f "http://<azure-qa-lb-ip>/health" && echo "Azure QA: UP"

# 3. Communicate to team
echo "ROLLBACK executed. Dev + QA back on Azure."

# 4. Investigate issue before retry
kubectl describe pods -n dev | grep -A 5 "Reason\|Message"
kubectl logs -n dev deployment/webapp --previous --tail=100
```

---

## Part 2 — Phase 2 Cutover (PreProd)

Same procedure as Dev/QA, using PreProd-specific IPs:

```bash
# Pre-flight check
PREPROD_LB=$(kubectl get svc webapp-svc -n preprod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -sf "http://${PREPROD_LB}/health" && echo "PreProd: PASS"

# DNS: preprod.company.com → 10.0.4.202

# Rollback: preprod.company.com → <azure-preprod-lb-ip>
```

---

## Part 3 — Production Cutover (Maintenance Window)

> **Required:** All Go/No-Go Gate P3 criteria must pass before starting.

### Pre-Window Preparation (48 hours before)

```bash
# 1. Lower production DNS TTL to 60 seconds
# prod.company.com: change TTL from 300 → 60

# 2. Final load test
# Run k6 or JMeter against on-prem prod at 150% of normal traffic
k6 run --vus 500 --duration 30m \
  -e BASE_URL="http://$(kubectl get svc webapp-svc -n prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')" \
  load-test.js

# 3. Verify pglogical is running and lag < 100ms
psql -h 10.0.5.15 -U postgres -c "
  SELECT subscription_name, status,
    extract(epoch from (now() - last_apply_time)) * 1000 AS lag_ms
  FROM pglogical.show_subscription_status();"

# 4. Ensure rollback procedure is documented and team trained
```

### Production Maintenance Window Script

```bash
#!/bin/bash
# prod-maintenance-cutover.sh
# Run during Saturday 22:00 maintenance window

set -e
LOG="/var/log/prod-cutover-$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

echo "===== PROD CUTOVER STARTED: $(date) ====="
echo "Operator: $(whoami) on $(hostname)"
echo ""

# ── STEP 1: Verify replication state ─────────────────────────────────────
echo "[STEP 1] Checking replication lag..."
PG_LAG=$(psql -h 10.0.5.15 -U postgres -t -c \
  "SELECT COALESCE(extract(epoch from (now() - last_apply_time)) * 1000, 999999)::int
   FROM pglogical.show_subscription_status() LIMIT 1;" 2>/dev/null)
echo "  pglogical lag: ${PG_LAG} ms"
[ "${PG_LAG:-999999}" -lt 2000 ] || { echo "ABORT: pglogical lag too high (${PG_LAG} ms)"; exit 1; }

MONGO_LAG=$(ssh oracle@10.0.5.25 "
  mongosh --quiet --eval \"
    var s = rs.status()
    var primary = s.members.filter(m => m.stateStr == 'PRIMARY')[0]
    var maxLag = Math.max(...s.members.filter(m => m.stateStr == 'SECONDARY').map(m =>
      (primary.optimeDate - m.optimeDate) / 1000
    ))
    print(maxLag)
  \"" 2>/dev/null)
echo "  MongoDB RS lag: ${MONGO_LAG} seconds"
awk "BEGIN {exit (${MONGO_LAG:-999} < 5) ? 0 : 1}" || { echo "ABORT: MongoDB lag too high"; exit 1; }

echo "  Replication lag: ACCEPTABLE — proceeding"
echo ""

# ── STEP 2: Freeze Azure Prod ─────────────────────────────────────────────
echo "[STEP 2] Freezing Azure Prod application..."
az aks get-credentials --resource-group rg-dls-coe-we-001 --name aks-prod --overwrite-existing
kubectl config use-context aks-prod
kubectl scale deployment --all --replicas=0 --namespace production
echo "  Azure Prod scaled to 0 replicas"
echo "  Waiting 60 seconds for in-flight requests to drain..."
sleep 60
echo ""

# ── STEP 3: Final replication flush ─────────────────────────────────────
echo "[STEP 3] Waiting for final replication flush (5 min)..."
sleep 300

# Check again after flush
FINAL_PG_LAG=$(psql -h 10.0.5.15 -U postgres -t -c \
  "SELECT COALESCE(extract(epoch from (now() - last_apply_time)) * 1000, 0)::int
   FROM pglogical.show_subscription_status() LIMIT 1;" 2>/dev/null)
echo "  Final pglogical lag: ${FINAL_PG_LAG} ms"
echo ""

# ── STEP 4: Drop replication subscription ────────────────────────────────
echo "[STEP 4] Dropping pglogical subscription (making on-prem writable)..."
psql -h 10.0.5.15 -U postgres -c \
  "SELECT pglogical.drop_subscription('azure-to-onprem-prod', true);"
echo "  pglogical subscription dropped"
echo ""

# ── STEP 5: Start on-prem Prod application ───────────────────────────────
echo "[STEP 5] Starting on-prem Prod application..."
kubectl config use-context vxrail-k8s
kubectl scale deployment webapp --replicas=3 --namespace prod

echo "  Waiting for pods to become ready..."
kubectl rollout status deployment/webapp -n prod --timeout=180s
echo ""

# ── STEP 6: Smoke tests ──────────────────────────────────────────────────
echo "[STEP 6] Running smoke tests..."
PROD_IP=$(kubectl get svc webapp-svc -n prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -sf "http://${PROD_IP}/health" && echo "  Health check: PASS" || {
  echo "  FAIL: health check failed — TRIGGERING ROLLBACK"
  bash prod-rollback.sh
  exit 1
}

curl -sf "http://${PROD_IP}/api/v1/status" | jq -r '.status' | grep -q "ok" && \
  echo "  API status: PASS" || echo "  API status: WARN — check manually"

echo ""

# ── STEP 7: Update DNS ───────────────────────────────────────────────────
echo "[STEP 7] *** UPDATE DNS NOW ***"
echo "  prod.company.com A record → ${PROD_IP}"
echo ""
read -p "  Press ENTER after DNS is updated to continue monitoring..."

# ── STEP 8: 15-minute monitoring ─────────────────────────────────────────
echo "[STEP 8] Monitoring for 15 minutes..."
for i in $(seq 1 15); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${PROD_IP}/health")
  echo "  $(date +%H:%M:%S) — HTTP status: $STATUS"
  [ "$STATUS" -eq 200 ] || echo "  WARNING: non-200 response at $(date)"
  sleep 60
done

echo ""
echo "===== CUTOVER COMPLETE: $(date) ====="
echo "Production is live on VxRail. Log: $LOG"
```

### Production Rollback Procedure

If anything goes wrong within the 2-hour rollback window:

```bash
#!/bin/bash
# prod-rollback.sh — must complete within 30 minutes

echo "===== PROD ROLLBACK STARTED: $(date) ====="

# 1. Scale down on-prem Prod immediately
kubectl config use-context vxrail-k8s
kubectl scale deployment webapp --replicas=0 -n prod
echo "[1] On-prem Prod scaled to 0"

# 2. Restart Azure Prod AKS deployment
az aks get-credentials --resource-group rg-dls-coe-we-001 --name aks-prod --overwrite-existing
kubectl config use-context aks-prod
kubectl scale deployment --all --replicas=3 --namespace production
echo "[2] Azure Prod restarted"

# 3. Wait for Azure Prod to be ready
kubectl rollout status deployment/webapp --namespace production --timeout=120s

# 4. Verify Azure Prod health
AZURE_PROD_IP=$(kubectl get svc webapp-svc --namespace production -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -sf "http://${AZURE_PROD_IP}/health" && echo "[3] Azure Prod: HEALTHY" || echo "[3] Azure Prod: DEGRADED — escalate"

# 5. Revert DNS
echo ""
echo "*** REVERT DNS: prod.company.com → ${AZURE_PROD_IP} ***"
echo "Action required: update DNS record manually NOW"

echo ""
echo "===== ROLLBACK COMPLETE: $(date) ====="
echo "Root cause analysis required before next attempt"
```

---

## Part 4 — Post-Cutover Monitoring (All Environments)

### 72-Hour Watch Metrics

For the 72 hours following each cutover, monitor:

```bash
# Key metrics to watch in Grafana:
# 1. HTTP error rate (should be < 0.1%)
# 2. P95 response time (should match or beat Azure baseline)
# 3. PostgreSQL query duration (pg_stat_activity)
# 4. MongoDB operation latency (mongostat)
# 5. K8s node CPU/memory pressure

# Quick health dashboard (run from jump host)
watch -n 30 '
echo "=== $(date) ==="
echo "Dev pods:";     kubectl get pods -n dev --no-headers | awk "{print $3}" | sort | uniq -c
echo "QA pods:";      kubectl get pods -n qa --no-headers | awk "{print $3}" | sort | uniq -c
echo "PreProd pods:"; kubectl get pods -n preprod --no-headers | awk "{print $3}" | sort | uniq -c
echo "Prod pods:";    kubectl get pods -n prod --no-headers | awk "{print $3}" | sort | uniq -c
echo "Nodes:";        kubectl get nodes --no-headers | awk "{print $2}" | sort | uniq -c
'
```

### Incident Escalation Matrix

| Severity | Condition | Response Time | Action |
|----------|-----------|--------------|--------|
| P1 Critical | App down OR data loss | < 15 min | Page on-call + DBA; consider rollback |
| P2 High | Error rate > 1% OR latency > 2x baseline | < 30 min | Investigate + notify stakeholders |
| P3 Medium | Single pod failure, non-critical alerts | < 2 hours | Fix during business hours |
| P4 Low | Slow query, monitoring gap | Next business day | Backlog |
