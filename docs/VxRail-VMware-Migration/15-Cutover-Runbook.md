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

---

## DNS Cutover — Step-by-Step Commands

### 24 Hours Before Cutover: Reduce TTL

```bash
# Check current DNS TTL on Azure DNS
# Azure Portal → DNS Zones → your zone → check TTL on relevant A records
# OR via CLI:
az network dns record-set list \
  --resource-group <rg-name> \
  --zone-name <your-zone> \
  --query "[?type=='Microsoft.Network/dnszones/A'].{name:name, ttl:ttl, ip:aRecords[0].ipv4Address}" \
  -o table

# Reduce Azure DNS TTL to 60 seconds (24h before cutover)
# This ensures that when you change the IP, propagation happens within 60 seconds
az network dns record-set a update \
  --resource-group <rg-name> \
  --zone-name <your-zone> \
  --name app-prod \
  --set ttl=60

# Confirm change
az network dns record-set a show \
  --resource-group <rg-name> \
  --zone-name <your-zone> \
  --name app-prod | grep ttl
# Should show: "ttl": 60
```

### During Cutover Window: DNS Switch

```bash
# Step 1: Verify on-prem app is healthy before switching
curl -sk https://10.0.4.210/health
# Expected: {"status":"healthy","version":"1.0.x"}

# Step 2: Note current Azure app IP (for rollback reference)
AZURE_IP=$(az network dns record-set a show \
  --resource-group <rg> --zone-name <zone> --name app-prod \
  | jq -r '.aRecords[0].ipv4Address')
echo "Azure IP: $AZURE_IP"  # Write this down

# Step 3: Update DNS to on-prem IP
ONPREM_IP="10.0.4.210"  # MetalLB LoadBalancer IP for Prod

az network dns record-set a update \
  --resource-group <rg> \
  --zone-name <zone> \
  --name app-prod \
  --set "aRecords[0].ipv4Address=${ONPREM_IP}"

# Step 4: Verify DNS change propagated
# From multiple locations (jump host, laptop, mobile hotspot):
nslookup app-prod.<your-zone> 8.8.8.8
# Should return: $ONPREM_IP

# Step 5: Monitor traffic shift
# On on-prem K8s (watch incoming requests):
kubectl logs -n prod -l app=nginx-ingress -f --tail=50

# Step 6: Verify app responds
curl -sk https://app-prod.<your-zone>/health
# Should return on-prem response (check version or hostname in response)
```

### Traffic Verification

```bash
# Check that traffic is hitting on-prem, not Azure
# Method 1: Check K8s ingress access logs
kubectl logs -n prod deployment/nginx-ingress-controller \
  --tail=100 | grep "GET /api"

# Method 2: Watch Grafana dashboard
# Panel: "HTTP Requests per minute" — should show increase on on-prem

# Method 3: Azure side — verify traffic dropped to 0
# Azure Portal → App Service / AKS → Metrics → HTTP requests
# Should drop to 0 within 2-3 minutes of DNS change
```

### Azure Resource Shutdown Sequence

```bash
# Shut down Azure resources in this ORDER (never reverse order)
# This prevents data loss and dependency issues

# 1. Scale down Azure K8s (AKS) to 0 nodes (preserves config but stops compute cost)
az aks scale --resource-group <rg> --name <aks-cluster> --node-count 0

# 2. Stop Azure Database (PostgreSQL)
# Flexible Server:
az postgres flexible-server stop --resource-group <rg> --name <db-server>
# Single Server (deprecated but some still have it):
az postgres server restart --resource-group <rg> --name <server> # Stop instead

# 3. Disable Cosmos DB (no "stop" available — reduce throughput to minimum)
az cosmosdb sql throughput update \
  --resource-group <rg> \
  --account-name <cosmos-account> \
  --database-name <db> \
  --throughput 400   # minimum RU/s = minimum cost

# 4. Stop Container Registry (ACR) - pause sync
az acr update --name <acr-name> --admin-enabled false

# WAIT 1 week before full deletion (rollback safety period)

# After 1 week — permanent deletion:
# az aks delete --resource-group <rg> --name <aks-cluster> --yes
# az postgres flexible-server delete --resource-group <rg> --name <server> --yes
# etc.
```

---

## Rollback Runbook (Execute Within 30 Minutes)

```bash
#!/bin/bash
# ROLLBACK SCRIPT — Execute if production cutover fails
# Time target: Complete rollback within 30 minutes of decision

echo "$(date): ROLLBACK INITIATED"
echo "$(date): Incident Commander: ______________"
echo "$(date): Reason: ______________"

# STEP 1 (minute 0-2): Revert DNS to Azure (highest priority)
AZURE_IP="<AZURE_IP_NOTED_BEFORE_CUTOVER>"

az network dns record-set a update \
  --resource-group <rg> \
  --zone-name <zone> \
  --name app-prod \
  --set "aRecords[0].ipv4Address=${AZURE_IP}"

echo "$(date): DNS reverted to Azure IP $AZURE_IP"

# Verify DNS propagation
sleep 10
RESOLVED=$(nslookup app-prod.<zone> 8.8.8.8 | grep Address | tail -1 | awk '{print $2}')
echo "$(date): DNS now resolves to: $RESOLVED"

# STEP 2 (minute 2-5): Restart Azure resources
echo "$(date): Restarting Azure resources..."
az aks scale --resource-group <rg> --name <aks-cluster> --node-count 3
az postgres flexible-server start --resource-group <rg> --name <db-server>

# STEP 3 (minute 5-10): Verify Azure app is responding
sleep 60  # Wait for AKS to scale up
curl -sk https://app-prod.<zone>/health
echo "$(date): Azure app health check above"

# STEP 4 (minute 10-15): Restore Azure DNS TTL to original value
az network dns record-set a update \
  --resource-group <rg> \
  --zone-name <zone> \
  --name app-prod \
  --set ttl=3600  # restore original TTL

echo "$(date): ROLLBACK COMPLETE"
echo "$(date): Please file a post-incident report within 24 hours"
```

---

## Azure Cost Verification After Cutover

```bash
# After full decommission, verify Azure costs dropped:

# Check current month's Azure spending
az consumption usage list \
  --start-date $(date -d "first day of this month" +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --query "[].{service:instanceName, cost:pretaxCost}" \
  --output table | sort -k2 -nr | head -20

# Create a budget alert so you know if Azure cost is unexpectedly high
az consumption budget create \
  --amount 1000 \
  --budget-name PostMigrationBudget \
  --category Cost \
  --time-grain Monthly \
  --time-period-start $(date +%Y-%m-01) \
  --time-period-end $(date -d "+12 months" +%Y-%m-01) \
  --notifications '[{"enabled":true,"operator":"GreaterThan","threshold":80,"contactEmails":["you@company.com"]}]'

echo "Budget alert set: email when Azure spend > 80% of $1000/month"
```

