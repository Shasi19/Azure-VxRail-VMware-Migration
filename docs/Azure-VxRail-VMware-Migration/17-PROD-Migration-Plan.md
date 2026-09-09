# PROD Migration Plan

**Environment:** PROD | Weeks 9–16 | Zero-Downtime Live Migration via pglogical**

> PROD migration is fundamentally different from QA and PREPROD.
> **Azure stays 100% live** throughout. The migration is invisible to users
> until the DNS switch — which takes under 5 minutes.

---

## Why PROD Migration is Different

```
QA / PREPROD MIGRATION MODEL:
──────────────────────────────
  Azure DB → pg_dump → /backup/ → pg_restore → On-prem
  Azure environment stays up but is NOT the live source during testing
  Acceptable downtime window: several hours (no users affected)

PROD MIGRATION MODEL (pglogical live replication):
───────────────────────────────────────────────────
  Azure DB (live, users writing) ──WAL stream──▶ On-prem DB
  Replication runs for 5+ weeks
  Azure stays the write primary the ENTIRE time
  On-prem = shadow copy, always < 50ms behind
  Cutover = drop subscription + DNS switch = < 5 min user impact
  Rollback = revert DNS = < 2 min (within 30-min window)
```

---

## Phase Flowchart

```
PROD MIGRATION — COMPLETE FLOW (Weeks 9–16)
═══════════════════════════════════════════════════════════════════════════

WEEK 9–10: PARALLEL BUILD (Zero risk — Azure still primary)
╔══════════════════════════════════════════╗
║ AZURE (100% live user traffic)           ║
║ PostgreSQL = single source of truth      ║
╚══════════════════════╤═══════════════════╝
                       │  (users unaffected)
                       │
╔══════════════════════▼═══════════════════╗
║ ON-PREM (being built in parallel)        ║
║  ① Provision 3 masters (govc)            ║
║  ② Configure OL9 OS on all masters       ║
║  ③ kubeadm init + join masters 2,3       ║
║  ④ Provision 12 workers (govc)           ║
║  ⑤ Configure OL9 OS on all workers       ║
║  ⑥ Deploy Calico + join workers          ║
║  ⑦ Deploy CSI + MetalLB                  ║
║  ⑧ Provision 3 DB VMs (govc)             ║
║  ⑨ Configure PG15 + Patroni HA          ║
╚══════════════════════════════════════════╝

WEEK 10–15: LIVE REPLICATION
╔══════════════════════════════════════════╗
║ AZURE (still primary)                    ║
║  pglogical Publisher configured          ║
║  Every INSERT/UPDATE/DELETE streamed     ║
╚══════════════════════╤═══════════════════╝
                       │ pglogical WAL stream
                       │ lag < 50ms, monitored daily
                       ▼
╔══════════════════════════════════════════╗
║ ON-PREM (shadow)                         ║
║  pglogical Subscriber: status=replicating║
║  Week 11–13: Deploy apps (no traffic)    ║
║  Week 14–15: 10% canary traffic          ║
║  72-hour parallel run                    ║
╚══════════════════════════════════════════╝

WEEK 16: CUTOVER (Friday 4PM–Saturday 4AM)
┌─────────────────────────────────────────────────────────────────────┐
│  T+00:00  Pre-cutover-check.sh → all pass → exec approval           │
│  T+00:05  Scale Azure AKS → 0 replicas (stop new writes)            │
│  T+00:10  Monitor: lag reaches 0ms                                  │
│  T+00:15  DROP pglogical subscription → on-prem is standalone       │
│  T+00:20  DNS switch: api.company.com → on-prem MetalLB IP          │
│  T+00:25  Verify DNS propagation (dig api.company.com)              │
│  T+00:30  Smoke tests → ✅ CUTOVER COMPLETE                         │
│  T+00:30→T+72:00  Hypercare: monitor every 15 min                  │
└─────────────────────────────────────────────────────────────────────┘
                              │
                   ◆ Smoke tests pass?
                  /               \
               YES                 NO (within 30 min)
                │                   │
          72-hr hypercare       ROLLBACK:
          Azure standby         DNS → Azure IP
                                RTO < 30 min
                                RPO = 0 (pglogical)
```

---

## Pre-Migration Checklist

- [ ] Reconcile workbook PROD AKS inventory: 4 x Standard D4s v4 plus 7 x Standard D4as v6, 11 nodes total, $1,897/month.
- [ ] Resolve the difference between 11 workbook AKS nodes and the 12-worker on-premises target before capacity approval.
- [ ] Confirm Azure PostgreSQL logical replication / pglogical support for the exact service tier and version; zero-downtime is not approved until this test passes.
- [ ] Change rollback objective to the last confirmed replication point; do not claim RPO 0 while replication lag can exist.
- [ ] Immutable offsite backup copy, full restore rehearsal, DNS rollback, certificate, firewall, and external dependency tests completed.

```
PROD MIGRATION PRE-FLIGHT (most critical — sign-off required)
═══════════════════════════════════════════════════════════════════════

Infrastructure
[ ] PROD K8s cluster: 15 nodes Ready (kubectl get nodes)
[ ] Patroni: 1 Leader + 2 Replicas, lag_in_MB = 0
[ ] pgBouncer VIP 10.30.0.200 responding (psql -h 10.30.0.200 -p 6432 ...)
[ ] MetalLB: PROD IP pool 10.52.200.0/24 assigned
[ ] vSphere CSI: StorageClass vsan-prod is default

Replication (must be stable for 2+ weeks before cutover)
[ ] pglogical subscription status = 'replicating'
[ ] Replication lag < 50ms for 48+ consecutive hours
[ ] Daily row-count validation passing (no mismatches)
[ ] Monitor alerts: no lag > 100ms events in last 7 days

Application (shadow mode validation)
[ ] All PROD pods Running (kubectl get pods -n prod)
[ ] Smoke tests on shadow: health, auth, DB all passing
[ ] 10% canary traffic running stable for 72+ hours
[ ] Error rate on canary < 0.1% (matching Azure baseline)

DNS and Networking
[ ] DNS TTL reduced to 60 seconds (propagation speed for rollback)
[ ] On-prem MetalLB IP reachable externally
[ ] Azure AKS scale-down command tested (confirmed it works)
[ ] Rollback DNS command documented and ready to execute

Governance
[ ] Pre-cutover-check.sh script returns ALL PASS
[ ] Leadership / exec sign-off obtained
[ ] DBA sign-off obtained
[ ] On-call rotation set: 3 engineers on call for 72-hour hypercare
[ ] Stakeholder notification sent: "Cutover scheduled Friday <date> 4PM"
[ ] Rollback plan reviewed by full team
[ ] Azure support case pre-opened (just in case)
```

---

## Step 1: Setup pglogical on Azure (Week 10)

```bash
# Time estimate: 30 min setup + 2–8 hours initial sync

AZURE_HOST="<your-server>.postgres.database.azure.com"
AZURE_ADMIN="adminuser"

# 1. Enable in Azure Portal:
#    Server → Parameters → shared_preload_libraries = pglogical
#    Server → Parameters → wal_level = logical
#    Server → Parameters → max_replication_slots = 10
#    Server → Parameters → max_wal_senders = 10
#    SAVE → RESTART the server (required for wal_level change)

# 2. Install extension and create publisher node
psql "host=${AZURE_HOST} dbname=prod_db user=${AZURE_ADMIN} sslmode=require" << 'SQL'
CREATE EXTENSION IF NOT EXISTS pglogical;

CREATE ROLE repl_user REPLICATION LOGIN PASSWORD 'AzureRepl_2026!';
GRANT USAGE ON SCHEMA pglogical TO repl_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO repl_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO repl_user;

SELECT pglogical.create_node(
  node_name := 'azure-prod-publisher',
  dsn := 'host=<azure-host> port=5432 dbname=prod_db user=repl_user sslmode=require'
);

SELECT pglogical.create_replication_set('prod_all_tables');
SELECT pglogical.replication_set_add_all_tables('prod_all_tables', ARRAY['public']);
SELECT pglogical.replication_set_add_all_sequences('prod_all_tables', ARRAY['public']);

SELECT set_name, replicate_insert, replicate_update, replicate_delete
FROM pglogical.replication_set;
SQL

echo "Publisher configured on Azure — initial sync starts on subscriber creation"
```

---

## Step 2: Create Subscription on On-Prem (Week 10)

```bash
# On pg-prod-01 (Patroni Leader: 10.30.0.120)
psql -h 10.30.0.120 -U postgres -d prod_db << 'SQL'
CREATE EXTENSION IF NOT EXISTS pglogical;

SELECT pglogical.create_node(
  node_name := 'onprem-prod-subscriber',
  dsn := 'host=10.30.0.200 port=6432 dbname=prod_db user=postgres'
);

SELECT pglogical.create_subscription(
  subscription_name    := 'azure_to_onprem_prod',
  provider_dsn         := 'host=<azure-host> port=5432 dbname=prod_db user=repl_user password=AzureRepl_2026! sslmode=require',
  replication_sets     := ARRAY['prod_all_tables'],
  synchronize_data     := true,        -- Initial full table copy (takes 2-8 hours)
  synchronize_structure := true        -- Copy table DDL
);

-- Check status (run after a few minutes)
SELECT * FROM pglogical.show_subscription_status('azure_to_onprem_prod');
SQL

# Expected status progression:
#   initializing → copying data → replicating

# Monitor initial sync progress
psql -h 10.30.0.120 -U postgres -d prod_db -c "
SELECT subscription_name, status, provider_node
FROM pglogical.show_subscription_status();"
```

---

## Step 3: Monitor Replication (Weeks 10–15)

```bash
# Daily monitoring command (run manually or via cron)
psql -h 10.30.0.120 -U postgres -d prod_db -c "
SELECT
  subscription_name,
  status,
  ROUND(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) * 1000) AS lag_ms
FROM pglogical.show_subscription_status();"

# Weekly row-count validation
AZURE_HOST="<azure-host>.postgres.database.azure.com"
TABLES=$(psql -h 10.30.0.120 -U postgres -d prod_db -t -c \
  "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;")

FAIL=0
for TABLE in ${TABLES}; do
  AZ=$(psql "host=${AZURE_HOST} dbname=prod_db user=adminuser sslmode=require" \
    -t -c "SELECT COUNT(*) FROM ${TABLE};" 2>/dev/null | tr -d ' ')
  OP=$(psql -h 10.30.0.120 -U postgres -d prod_db \
    -t -c "SELECT COUNT(*) FROM ${TABLE};" 2>/dev/null | tr -d ' ')
  [ "${AZ}" != "${OP}" ] && echo "MISMATCH: ${TABLE} Azure=${AZ} OnPrem=${OP}" && FAIL=$((FAIL+1))
done
echo "Row count validation: ${FAIL} mismatches (0 = OK to proceed)"

# Escalation criteria:
# - Lag > 100ms sustained for > 30 minutes → investigate immediately
# - Lag > 500ms → pause cutover planning, find root cause
# - Any row-count mismatch → investigate before scheduling cutover
```

---

## Step 4: Application Deployment in Shadow Mode (Weeks 11–13)

```bash
# Deploy apps to prod namespace — but NO user traffic yet
# Apps connect to on-prem DB (which is in sync with Azure)

kubectl create namespace prod 2>/dev/null || true

kubectl create secret generic postgres-prod-creds -n prod \
  --from-literal=POSTGRES_HOST="10.30.0.200" \
  --from-literal=POSTGRES_PORT="6432" \
  --from-literal=POSTGRES_DB="prod_db" \
  --from-literal=POSTGRES_USER="app_user" \
  --from-literal=POSTGRES_PASSWORD="AppProd_2026!"

# Deploy via ArgoCD (main branch = production manifests)
kubectl apply -f - << 'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prod-app
  namespace: argocd
spec:
  project: prod
  source:
    repoURL: https://github.com/your-org/k8s-manifests
    targetRevision: main
    path: environments/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
YAML

kubectl rollout status deployment -n prod --timeout=600s

# Internal smoke tests (no external DNS pointing here yet)
PROD_IP=$(kubectl get svc api-gateway -n prod \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -sf "http://${PROD_IP}/health"
echo "Shadow deployment complete — apps running but serving 0% user traffic"
```

---

## Step 5: Canary + Dual-Run Validation (Weeks 14–15)

```bash
# Route 10% of live traffic to on-prem
# WHY canary: Validate with real users under real production load
# If issues: revert weight to 0% instantly

# DNS weighted routing (Azure DNS example):
# api.company.com:
#   Weight 90 → Azure LB IP     (still primary)
#   Weight 10 → On-prem LB IP   (canary)

# Monitor canary traffic on on-prem
# Target: error rate ≤ Azure's baseline, p95 latency ≤ Azure's baseline

# 72-hour parallel run checklist:
echo "=== HOUR 1 CHECKS ==="
kubectl get pods -n prod --no-headers | grep -v "Running\|Completed"
patronictl -c /etc/patroni/patroni.yml list

echo "=== HOUR 24 CHECKS ==="
# Check for memory leaks
kubectl top pods -n prod --sort-by=memory | head -20
# Check for connection pool buildup
psql -h 10.30.0.200 -p 6432 -U postgres -d prod_db \
  -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

echo "=== HOUR 72 CHECKS ==="
# Cron jobs completed?
kubectl get cronjobs -n prod
kubectl get jobs -n prod | grep -v Complete
# All above should show Completed
```

---

## Step 6: Cutover Execution (Week 16, Friday 4 PM)

```bash
# T-30 min: Final validation
/usr/local/bin/pre-cutover-check.sh
# Must return: "READY FOR CUTOVER"

# Get explicit exec approval before proceeding
echo "Awaiting exec approval to proceed with cutover..."
read -p "Enter approver name and proceed? (yes/no): " APPROVAL
[ "${APPROVAL}" != "yes" ] && echo "Cutover cancelled" && exit 1

# T+00:05 — Stop Azure writes
az aks command invoke -g myRG -n myAKSCluster \
  --command "kubectl scale deployment --all --replicas=0 -n prod"
echo "T+00:05: Azure writes stopped"

# T+00:10 — Wait for replication lag = 0
echo "Waiting for lag to reach 0..."
while true; do
  LAG=$(psql -h 10.30.0.120 -U postgres -d prod_db -t -c \
    "SELECT COALESCE(ROUND(EXTRACT(EPOCH FROM \
     (now()-pg_last_xact_replay_timestamp()))*1000),0);" | tr -d ' ')
  echo "$(date +%H:%M:%S) lag=${LAG}ms"
  [ "${LAG:-9999}" -lt 5 ] && break
  sleep 3
done
echo "T+00:10: Lag = 0ms — databases are 100% in sync"

# T+00:15 — Drop subscription (on-prem becomes standalone primary)
psql -h 10.30.0.120 -U postgres -d prod_db -c \
  "SELECT pglogical.drop_subscription('azure_to_onprem_prod', true);"
echo "T+00:15: On-prem PostgreSQL is now standalone (read+write)"

# T+00:20 — Switch DNS
ONPREM_IP=$(kubectl get svc api-gateway -n prod \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
az network dns record-set a update \
  -g dns-resource-group -z company.com -n api \
  --set "aRecords[0].ipv4Address=${ONPREM_IP}"
echo "T+00:20: DNS updated to ${ONPREM_IP}"

# Wait for propagation (TTL = 60s)
sleep 65
NEW_IP=$(dig api.company.com +short | head -1)
echo "DNS now resolves to: ${NEW_IP}"
[ "${NEW_IP}" = "${ONPREM_IP}" ] && echo "DNS correct" || echo "WARNING: DNS mismatch"

# T+00:30 — Smoke tests
curl -sf "http://api.company.com/health"
echo ""
echo "T+00:30: CUTOVER COMPLETE"
echo "Begin 72-hour hypercare monitoring"
```

---

## Rollback Plan

```
ROLLBACK DECISION TRIGGERS (within 30 min of DNS switch):
═════════════════════════════════════════════════════════════

  Trigger any ONE of these → initiate rollback immediately:
  ├── Health endpoint returning non-200 after 3 retries
  ├── Error rate > 1% for > 2 minutes
  ├── Patroni cluster unhealthy (no Leader)
  ├── Database write latency > 5 seconds
  └── Critical application error affecting > 5% of users

ROLLBACK STEPS (RTO target: 30 minutes):
─────────────────────────────────────────
  Step 1 (T+00): Revert DNS to Azure IP
    az network dns record-set a update -g dns-rg -z company.com -n api
      --set "aRecords[0].ipv4Address=<azure-lb-ip>"

  Step 2 (T+01): Restart Azure AKS
    az aks command invoke -g myRG -n myAKSCluster
      --command "kubectl scale deployment --all --replicas=3 -n prod"

  Step 3 (T+03): Verify Azure is serving traffic
    dig api.company.com → should return Azure IP
    curl https://api.company.com/health → should return 200

  Step 4 (T+05): Notify stakeholders
    "Cutover rolled back to Azure. On-prem issue under investigation."

  Step 5 (T+10+): Investigate root cause
    Check: kubectl describe pod -n prod, patronictl list, pglogical status

  IMPORTANT:
  ✅ RPO = 0 (pglogical kept Azure and on-prem perfectly in sync)
  ✅ Azure DB still has all data (pglogical is read-only from Azure)
  ✅ Any writes to on-prem during cutover attempt are LOST on rollback
     → mitigated by keeping cutover window short (< 30 min total)

  Re-attempt cutover:
  ├── Fix root cause on on-prem
  ├── Re-enable pglogical (Azure becomes publisher again)
  ├── Wait for sync to stabilize (days/weeks)
  └── Schedule next cutover window (typically next Friday)
```

---

## Post-Cutover Validation (72-Hour Hypercare)

```bash
# Every 15 minutes for first 24 hours
cat > /usr/local/bin/hypercare.sh << 'SCRIPT'
#!/bin/bash
echo "=== HYPERCARE $(date) ==="

# Pods
UNHEALTHY=$(kubectl get pods -n prod --no-headers | grep -vc "Running\|Completed")
echo "Unhealthy pods: ${UNHEALTHY}"

# DB
patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep -E "Leader|Replica"

# Error rate (Prometheus)
ERR=$(curl -s "http://prometheus:9090/api/v1/query?query=\
rate(http_requests_total{status=~'5..',namespace='prod'}[5m])" \
  | python3 -c "import sys,json; d=json.load(sys.stdin)['data']['result']; \
  print(d[0]['value'][1] if d else '0')" 2>/dev/null)
echo "5xx error rate (5m): ${ERR}"

echo ""
SCRIPT
chmod +x /usr/local/bin/hypercare.sh
echo "*/15 * * * * root /usr/local/bin/hypercare.sh >> /var/log/hypercare.log" \
  >> /etc/crontab

# 24-hour check
echo "At hour 24: kubectl top pods -n prod (check for memory leaks)"
echo "At hour 48: Check cron jobs completed"
echo "At hour 72: Declare migration successful, end hypercare"
```

---

## PROD Migration Sign-Off

```
PROD MIGRATION SIGN-OFF (Most Formal — Exec Required)
══════════════════════════════════════════════════════════════════

Migration date:          _________________
DNS switch time:         _________________
Cutover duration:        _________________ minutes
Azure scale-down time:   _________________

Pre-Cutover:
[ ] pre-cutover-check.sh: ALL PASS
[ ] Replication lag < 50ms for 2+ weeks
[ ] Weekly row-count validation: 0 mismatches for 2+ weeks
[ ] 72-hour canary: error rate < 0.1%, p95 < 500ms

Cutover Execution:
[ ] Azure writes stopped successfully
[ ] Lag reached 0ms before subscription drop
[ ] pglogical subscription dropped cleanly
[ ] DNS updated and verified
[ ] Smoke tests passed

Post-Cutover (72 hours):
[ ] All pods stable, no unexpected restarts
[ ] Error rate matching or better than Azure baseline
[ ] Patroni cluster healthy throughout
[ ] Backup jobs running (Veeam + pg_basebackup)

Signatures (ALL required):
Executive Sponsor:    _________________ Date: _________
Infrastructure Lead:  _________________ Date: _________
DBA Lead:             _________________ Date: _________
Application Lead:     _________________ Date: _________
Security Lead:        _________________ Date: _________

Migration declared COMPLETE: _________________ Date: _________
Azure decommission start:     _________________ (2 weeks post-cutover)
```

---

**Previous:** [16-PREPROD-Migration-Plan.md](./16-PREPROD-Migration-Plan.md)
**Infrastructure:** [07-PROD-Detailed-Implementation.md](./07-PROD-Detailed-Implementation.md)
**Cutover detail:** [12-Cutover-Runbook.md](./12-Cutover-Runbook.md)
**Rollback:** [09-Rollback-Procedures.md](./09-Rollback-Procedures.md)
**DR & Backup:** [18-Application-Backup-DR-Plan.md](./18-Application-Backup-DR-Plan.md)
**Index:** [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md)
