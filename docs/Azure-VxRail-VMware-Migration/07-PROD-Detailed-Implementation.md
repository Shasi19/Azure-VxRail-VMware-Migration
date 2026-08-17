# PROD Environment — Detailed Implementation Guide

**Phase 4 | Weeks 9–16 | pglogical Live Replication + Zero-Downtime Cutover**

> **Environment Specs:** k8s-prod | VLAN 120 (10.52.0.0/16) | 3 Masters + 12 Workers  
> **Prerequisite:** PREPROD sign-off complete, all gates passed  
> **Critical Principle:** Azure stays running until DNS is switched — zero downtime

---

## 📊 Phase Overview

```
PROD MIGRATION FLOWCHART (Weeks 9–16)
═════════════════════════════════════════════════════════════════════════

AZURE PRODUCTION (still serving live traffic throughout)
╔══════════════════════════════════════════════════════════════════╗
║  AKS Workloads ←── Users still connecting ──→ Azure DNS/LB      ║
║  Azure PostgreSQL (primary source of truth)                      ║
╚════════════════════╤═════════════════════════════════════════════╝
                     │ pglogical REPLICATION (Week 10+)
                     │ All writes flow: Azure → On-prem
                     ▼
ON-PREM (being built while Azure runs)
╔══════════════════════════════════════════════════════════════════╗
║  ① WEEK 9-10: PROD infrastructure build                         ║
║      ├── 12 Worker nodes provisioned                             ║
║      ├── Patroni HA PostgreSQL (3 nodes)                         ║
║      ├── Kubernetes PROD cluster                                 ║
║      └── Harbor, ArgoCD, MetalLB configured                      ║
║                                                                  ║
║  ② WEEK 10-11: pglogical replication setup                       ║
║      ├── Extension installed on Azure PostgreSQL                 ║
║      ├── Publication created (Azure = publisher)                  ║
║      ├── Subscription created (on-prem = subscriber)             ║
║      └── Live sync: every INSERT/UPDATE/DELETE replicated         ║
║                                                                  ║
║  ③ WEEK 11-13: Application deployment (shadow mode)              ║
║      ├── Apps deployed to on-prem PROD namespace                 ║
║      ├── Connected to on-prem database                           ║
║      ├── NOT receiving live traffic yet                          ║
║      └── Internal testing and smoke tests                        ║
║                                                                  ║
║  ④ WEEK 14-15: Dual-run validation                               ║
║      ├── 10% canary traffic to on-prem (blue-green)              ║
║      ├── Monitor for 2+ weeks: latency, errors, data consistency  ║
║      ├── Replication lag < 50ms consistently                     ║
║      └── Stakeholder sign-off for cutover                        ║
╚══════════════════════════════════════════════════════════════════╝
                     │
                     ▼
  ⑤ WEEK 16: CUTOVER (Friday 4PM – Saturday 4AM)
  ┌────────────────────────────────────────────────────────────────┐
  │  T+00:00  Put Azure in maintenance mode (block new writes)     │
  │  T+00:05  Wait for pglogical lag to reach 0                   │
  │  T+00:10  Promote on-prem PostgreSQL to standalone (no replica)│
  │  T+00:15  Switch DNS: azure.company.com → on-prem LB IP       │
  │  T+00:20  Smoke tests on on-prem PROD                         │
  │  T+00:30  ✅ CUTOVER COMPLETE — on-prem is now live           │
  │  T+00:30 to T+12:00  Monitor intensively (72-hour hypercare)   │
  └────────────────────────────────────────────────────────────────┘
                     │
           ◆ Success?
          /           \
       YES              NO (within 30 min)
        │                │
  Monitor 72h        ROLLBACK:
  Azure decommission  DNS back to Azure
  (Week 17-32)        RTO < 30 minutes
```

---

## Week 9–10: PROD Infrastructure Build

### Why We Do This While Azure Still Runs

The critical design principle for PROD migration:
- **Azure stays live** — users never experience downtime during build phase
- **On-prem is built in parallel** — no rush, no pressure, no downtime risk
- **pglogical keeps databases in sync** — when we cut over, data is already there
- **We can rollback at any point** — until DNS is switched, Azure is still primary

```
PARALLEL OPERATION ARCHITECTURE (Weeks 9-15)
═══════════════════════════════════════════════════════════════

   USER TRAFFIC                    BACKEND SYNC
         │                               │
         ▼                               ▼
  ┌─────────────────┐          ┌───────────────────────┐
  │   AZURE (LIVE)  │          │  pglogical replication │
  │   Serving 100%  │──WAL──▶  │  Azure → On-prem       │
  │   of traffic    │  stream  │  lag < 50ms             │
  └─────────────────┘          └───────────────────────┘
                                          │
                               ┌──────────▼──────────┐
                               │  ON-PREM (SHADOW)   │
                               │  Shadow database     │
                               │  Shadow apps (0%     │
                               │  user traffic)       │
                               └─────────────────────┘

  WHY shadow mode:
  - On-prem database stays fully in sync
  - App team can test against real-data copy
  - Performance profiling under realistic data set
  - Bug detection before going live
```

### Step 1: Provision 12 Worker Nodes

```bash
# On vCenter jump host — clone 12 workers from Oracle Linux 9 template
# WHY 12 workers: Production scale — 4 workers per availability zone
# PROD uses more memory per pod (more replicas, more resources)

for i in $(seq -f "%02g" 1 12); do
  govc vm.clone \
    -vm "/Datacenter/vm/Templates/ol9-k8s-template" \
    -ds "vsanDatastore" \
    -pool "/Datacenter/host/VxRail-Cluster/Resources/PROD" \
    -net "VLAN-120-PROD" \
    -name "k8s-prod-worker-${i}" \
    -m 65536 \    # 64 GB RAM (more than PREPROD's 32 GB)
    -c 16 \       # 16 vCPUs (2x PREPROD)
    -on=false
  
  govc vm.power -on "k8s-prod-worker-${i}"
  echo "✅ Created k8s-prod-worker-${i}"
done

# After OS boots, configure networking on each node (same as PREPROD)
# IP range: 10.52.1.101 through 10.52.1.112

# Join to PROD K8s cluster (same join procedure as PREPROD)
# On PROD master: JOIN_CMD=$(kubeadm token create --print-join-command)
# On each worker: ${JOIN_CMD} --node-name=$(hostname)

# Verify all 15 nodes (3 masters + 12 workers)
kubectl get nodes | grep k8s-prod
# Expected: 15 nodes in Ready state
```

### Step 2: Setup Patroni HA for PROD

```bash
# PROD PostgreSQL uses larger nodes than PREPROD
# WHY: Production PostgreSQL needs more memory for caching the larger dataset

# Create 3 PROD PostgreSQL VMs
for i in 01 02 03; do
  govc vm.clone \
    -vm "/Datacenter/vm/Templates/ol9-base-template" \
    -ds "vsanDatastore" \
    -pool "/Datacenter/host/VxRail-Cluster/Resources/PROD-DB" \
    -net "VLAN-30-DATABASE" \
    -name "pg-prod-${i}" \
    -m 131072 \   # 128 GB RAM for PROD (2x PREPROD)
    -c 32 \       # 32 vCPUs
    -on=false
done
# IP addresses: pg-prod-01: 10.30.0.120, pg-prod-02: 10.30.0.121, pg-prod-03: 10.30.0.122
# VIP (pgBouncer): 10.30.0.200

# Install PostgreSQL 15 + Patroni (same steps as PREPROD Week 4)
# Key difference: PROD patroni.yml uses larger resources

# PROD-specific patroni.yml changes (differences from PREPROD):
# scope: prod-postgres
# name: pg-prod-01 (02, 03)
# listen: 10.30.0.120:5432 (different IP per node)

# PROD PostgreSQL parameters (tuned for 128 GB RAM):
# shared_buffers: 32GB           (was 16GB in PREPROD)
# effective_cache_size: 96GB     (was 48GB)
# max_connections: 600           (was 400 — more app instances)
# work_mem: 128MB                (was 64MB)
# maintenance_work_mem: 4GB      (was 2GB)

# Start Patroni on pg-prod-01 first, then 02 and 03
# (Same sequence as PREPROD — 01 becomes primary)
```

### Step 3: Configure PROD Kubernetes Namespace

```bash
# Create PROD namespace with strict resource quotas
# WHY: PROD should have guaranteed resources — QA/PREPROD cannot starve PROD

kubectl create namespace prod

# Apply PROD-specific resource limits (higher than PREPROD)
kubectl create resourcequota prod-quota --namespace prod \
  --hard=requests.cpu=192,requests.memory=384Gi,limits.cpu=384,limits.memory=768Gi

# Apply Priority Class for PROD workloads
# WHY: PriorityClass ensures PROD pods are scheduled first
# If cluster is under memory pressure, QA pods are evicted, not PROD
cat > prod-priority-class.yaml << 'EOF'
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: production-critical
value: 1000000
globalDefault: false
description: "Critical production workloads — highest scheduling priority"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: production-high
value: 900000
globalDefault: false
description: "Non-critical production workloads"
EOF
kubectl apply -f prod-priority-class.yaml

# Apply network policy — PROD pods cannot be reached from QA/PREPROD
# WHY: Defense in depth — environment isolation at network level
cat > prod-network-policy.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prod-isolation
  namespace: prod
spec:
  podSelector: {}      # Applies to all pods in prod namespace
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: prod   # Only from prod namespace
    - ipBlock:
        cidr: 10.52.0.0/16   # PROD VLAN
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: prod
    - ipBlock:
        cidr: 10.30.0.0/24   # Database VLAN
    - ipBlock:
        cidr: 0.0.0.0/0      # External internet (for APIs, etc.)
      ports:
      - port: 443
EOF
kubectl apply -f prod-network-policy.yaml
```

---

## Week 10–11: pglogical Live Replication Setup

### What is pglogical and Why Use It?

```
PGLOGICAL vs ALTERNATIVES
══════════════════════════════════════════════════════════

  Option 1: pg_dump/restore (USED FOR QA/PREPROD)
  ┌─────────────────────────────────────────────────────┐
  │ Azure PostgreSQL ──dump──▶ file ──restore──▶ On-prem │
  │ ✅ Simple                                            │
  │ ❌ Requires DOWNTIME (maintenance window to dump)    │
  │ ❌ Not suitable for PROD (TB-sized databases)        │
  └─────────────────────────────────────────────────────┘

  Option 2: pglogical (USED FOR PROD) ← WE USE THIS
  ┌─────────────────────────────────────────────────────┐
  │ Azure PostgreSQL ──WAL stream──▶ On-prem PostgreSQL │
  │ ✅ ZERO DOWNTIME — Azure keeps running              │
  │ ✅ Real-time sync — every commit replicated         │
  │ ✅ Selective — can replicate specific tables        │
  │ ✅ Can run for weeks until we're ready to cut over  │
  │ ⚠️  Requires pglogical extension on both ends      │
  │ ⚠️  Azure PostgreSQL must be Flexible Server       │
  └─────────────────────────────────────────────────────┘

  HOW IT WORKS:
  1. Azure PostgreSQL writes to WAL (Write-Ahead Log)
  2. pglogical reads WAL changes (logical decoding)
  3. Changes streamed over network to on-prem subscriber
  4. On-prem applies changes in same order
  5. On-prem is always nearly-current (lag < 50ms)
  6. At cutover: stop writes to Azure, wait for lag=0, promote on-prem
```

### Step 1: Install pglogical on Azure PostgreSQL

```bash
# On Azure PostgreSQL Flexible Server (via Azure CLI or portal)
# WHY: pglogical must be enabled as a server extension before use

# Enable pglogical extension in Azure portal:
# PostgreSQL server → Server parameters →
#   shared_preload_libraries = pglogical
#   wal_level = logical                  ← REQUIRED for logical replication
#   max_replication_slots = 10           ← One slot per subscriber
#   max_wal_senders = 10                 ← One WAL sender per replica

# Connect to Azure PostgreSQL and install extension
AZURE_PG_HOST="your-server.postgres.database.azure.com"
AZURE_PG_USER="adminuser"

psql "host=${AZURE_PG_HOST} port=5432 dbname=prod_db user=${AZURE_PG_USER} sslmode=require" << 'SQL'
-- Install pglogical extension
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Create replication user (least privilege)
-- WHY: Dedicated user for replication only; not the admin account
CREATE ROLE replication_user REPLICATION LOGIN
  PASSWORD 'SecureReplUser2026!';

GRANT USAGE ON SCHEMA pglogical TO replication_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
  GRANT SELECT ON TABLES TO replication_user;

-- Create pglogical NODE on publisher (Azure = source)
SELECT pglogical.create_node(
  node_name := 'azure-prod-publisher',
  dsn := 'host=${AZURE_PG_HOST} port=5432 dbname=prod_db user=replication_user password=SecureReplUser2026! sslmode=require'
);

-- Create REPLICATION SET — define WHAT to replicate
-- WHY replication sets: Fine-grained control; exclude system tables, temp tables
SELECT pglogical.create_replication_set('prod_replication_set');

-- Add ALL tables to the replication set
-- WHY: We want a complete copy for zero-downtime cutover
SELECT pglogical.replication_set_add_all_tables('prod_replication_set', ARRAY['public']);
SELECT pglogical.replication_set_add_all_sequences('prod_replication_set', ARRAY['public']);

-- Verify publication is set up
SELECT * FROM pglogical.replication_set;
SQL
echo "✅ pglogical configured on Azure PostgreSQL"
```

### Step 2: Install pglogical on On-Premises PostgreSQL

```bash
# On pg-prod-01 (the PROD Patroni leader)
# WHY: On-prem is the SUBSCRIBER — it receives changes from Azure

# Install pglogical extension
dnf install -y postgresql15-pglogical

# Add to PostgreSQL config
cat >> /data/patroni/postgresql.conf << 'EOF'
shared_preload_libraries = 'pglogical'
wal_level = logical              # Required even on subscriber side
max_replication_slots = 10
max_wal_senders = 10
EOF

# Restart PostgreSQL (via Patroni)
patronictl -c /etc/patroni/patroni.yml restart prod-postgres --force

# Connect to on-prem PostgreSQL and set up subscriber
psql -h 10.30.0.120 -U postgres -d prod_db << 'SQL'
-- Install pglogical on on-prem
CREATE EXTENSION IF NOT EXISTS pglogical;

-- Create NODE on subscriber (on-prem = destination)
SELECT pglogical.create_node(
  node_name := 'onprem-prod-subscriber',
  dsn := 'host=10.30.0.200 port=6432 dbname=prod_db user=postgres password=SecureAdminPass2026!'
);

-- Create SUBSCRIPTION — pull from Azure publisher
-- WHY: The subscription defines the connection from subscriber (on-prem)
-- to publisher (Azure) and starts the replication stream
SELECT pglogical.create_subscription(
  subscription_name := 'azure_to_onprem_prod',
  provider_dsn := 'host=your-server.postgres.database.azure.com port=5432 dbname=prod_db user=replication_user password=SecureReplUser2026! sslmode=require',
  replication_sets := ARRAY['prod_replication_set'],
  synchronize_data := true,       -- Initial full copy first
  synchronize_structure := true   -- Copy table structure (DDL)
);

-- Verify subscription status
SELECT * FROM pglogical.show_subscription_status('azure_to_onprem_prod');
SQL

echo "✅ pglogical subscription created — initial sync starting"
echo "Initial sync will take 1-6 hours depending on database size"
```

### Step 3: Monitor Replication

```bash
# CRITICAL: Monitor replication lag continuously during weeks 10-15
# WHY: Any lag > 50ms consistently indicates a problem that needs fixing
# before cutover; we want lag near 0 for 2+ stable weeks

# Create monitoring script (run every 5 minutes via cron)
cat > /usr/local/bin/check-replication-lag.sh << 'EOF'
#!/bin/bash

# Check on-prem subscriber lag
LAG=$(psql -h 10.30.0.120 -U postgres -d prod_db -t -c "
SELECT 
  EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) * 1000 AS lag_ms
FROM pg_stat_wal_receiver;" | tr -d ' ')

echo "$(date) Replication lag: ${LAG}ms"

# Alert if lag > 100ms
if (( $(echo "$LAG > 100" | bc -l) )); then
  echo "⚠️  WARNING: Replication lag ${LAG}ms > 100ms threshold"
  # Send alert (integrate with your alerting system)
fi

# Check pglogical subscription status
psql -h 10.30.0.120 -U postgres -d prod_db -c "
SELECT 
  subscription_name,
  status,
  provider_node,
  replication_sets
FROM pglogical.show_subscription_status();"
EOF

chmod +x /usr/local/bin/check-replication-lag.sh

# Add to cron (every 5 minutes)
echo "*/5 * * * * postgres /usr/local/bin/check-replication-lag.sh >> /var/log/pg-replication-lag.log 2>&1" \
  >> /etc/crontab

# View replication status from Prometheus metric
# (if pg_exporter is configured with pglogical queries)
curl -s http://10.30.0.120:9187/metrics | grep pglogical

# Grafana dashboard: check "PostgreSQL Replication Lag" panel
# Target: Consistently < 50ms for 2+ weeks before cutover
```

### Step 4: Validate Data Consistency

```bash
# WHY data validation: Detect silent replication issues before cutover
# pglogical can miss data if: schema changes, table exclusions, network blips

# Run data consistency check (compare Azure vs On-prem row counts)
cat > /tmp/validate-replication.sh << 'EOF'
#!/bin/bash
AZURE_CONN="host=your-server.postgres.database.azure.com port=5432 dbname=prod_db user=adminuser sslmode=require"
ONPREM_CONN="host=10.30.0.120 port=5432 dbname=prod_db user=postgres"

echo "=== REPLICATION VALIDATION REPORT $(date) ==="
echo ""

# Get list of tables
TABLES=$(psql "${ONPREM_CONN}" -t -c "
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;")

PASS=0
FAIL=0

for TABLE in $TABLES; do
  AZURE_COUNT=$(psql "${AZURE_CONN}" -t -c "SELECT COUNT(*) FROM public.${TABLE};" 2>/dev/null | tr -d ' ')
  ONPREM_COUNT=$(psql "${ONPREM_CONN}" -t -c "SELECT COUNT(*) FROM public.${TABLE};" 2>/dev/null | tr -d ' ')
  
  if [ "${AZURE_COUNT}" = "${ONPREM_COUNT}" ]; then
    echo "✅ ${TABLE}: ${AZURE_COUNT} rows (match)"
    ((PASS++))
  else
    echo "❌ ${TABLE}: Azure=${AZURE_COUNT}, On-prem=${ONPREM_COUNT} (MISMATCH!)"
    ((FAIL++))
  fi
done

echo ""
echo "Results: ${PASS} tables match, ${FAIL} tables MISMATCH"
if [ $FAIL -gt 0 ]; then
  echo "⚠️  ACTION REQUIRED: Investigate mismatches before proceeding"
  exit 1
fi
exit 0
EOF

chmod +x /tmp/validate-replication.sh
/tmp/validate-replication.sh
# Should show 0 mismatches — run daily during replication phase
```

---

## Week 11–13: Application Deployment (Shadow Mode)

### Step 1: Deploy Apps to PROD Namespace (No Live Traffic Yet)

```bash
# WHY shadow mode: Test against real production data without serving real users
# Any bugs discovered here = fixed before cutover = no user impact

# Create ArgoCD application for PROD
cat > argocd-prod-app.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prod-application
  namespace: argocd
spec:
  project: prod
  source:
    repoURL: https://github.com/your-org/k8s-manifests
    targetRevision: main    # Deploy from 'main' branch (production)
    path: environments/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
  syncPolicy:
    automated:
      prune: false        # DON'T auto-prune in PROD — require manual review
      selfHeal: false     # DON'T auto-heal in PROD — alert on drift instead
    syncOptions:
    - CreateNamespace=false     # Namespace already exists
    - PrunePropagationPolicy=foreground
EOF
kubectl apply -f argocd-prod-app.yaml

# All pods should start in shadow mode
# The app connects to on-prem PostgreSQL (which is in sync with Azure)
kubectl get pods -n prod -w
# Wait for all pods to be Running

# Verify app can query database
kubectl exec -n prod deployment/api-gateway -- \
  curl -s http://localhost:8080/health
# Expected: {"status": "healthy", "database": "connected"}
```

### Step 2: Internal Smoke Tests

```bash
# Test PROD environment without routing user traffic
# Access via internal IP or test DNS entry (not production DNS)

PROD_INTERNAL_IP=$(kubectl get svc api-gateway -n prod \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "PROD shadow IP: ${PROD_INTERNAL_IP}"

# Add test DNS entry (NOT changing production DNS)
echo "${PROD_INTERNAL_IP} prod-shadow.internal.company.com" >> /etc/hosts

# Run smoke tests against shadow environment
SMOKE_RESULTS=()

# Core API health
STATUS=$(curl -sf http://${PROD_INTERNAL_IP}/health && echo "PASS" || echo "FAIL")
SMOKE_RESULTS+=("Health check: $STATUS")

# Authentication
AUTH=$(curl -sf -X POST http://${PROD_INTERNAL_IP}/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"smoke@test.com","password":"smokepass"}' | \
  jq -r '.status' 2>/dev/null)
SMOKE_RESULTS+=("Auth: $AUTH")

# Database read
DB_READ=$(curl -sf http://${PROD_INTERNAL_IP}/api/users/count | jq -r '.count' 2>/dev/null)
SMOKE_RESULTS+=("DB read (user count): ${DB_READ}")

# Print results
echo "=== SMOKE TEST RESULTS ==="
for result in "${SMOKE_RESULTS[@]}"; do
  echo "  $result"
done
```

---

## Week 14–15: Dual-Run & Pre-Cutover Validation

### Canary Traffic Routing (10% to On-prem)

```bash
# WHY canary: Validate with real users before full cutover
# 10% of traffic goes to on-prem; if issues → stop immediately

# Update DNS with weighted routing (using split-horizon DNS or traffic manager)
# Route 10% to on-prem LoadBalancer IP, 90% to Azure

# Using your DNS provider's weighted routing:
# Record: api.company.com
#   → Azure LB IP (weight: 90)
#   → On-prem MetalLB IP (weight: 10)

# Monitor the 10% on-prem traffic carefully
kubectl logs -f deployment/api-gateway -n prod | grep -E 'ERROR|WARN|exception' &

# Watch error rates in Prometheus
# Target: Error rate on on-prem < 0.1% (same as Azure)
# If on-prem error rate > Azure: rollback DNS to 100% Azure
```

### 72-Hour Parallel Run Checklist

```bash
# WHY 72 hours: Catches issues that don't appear immediately
# - Memory leaks (appear after hours)
# - Connection pool exhaustion (appears at peak hours)
# - Cron job failures (appear daily/weekly)
# - Edge case bugs (appear with diverse real traffic)

echo "=== 72-HOUR PARALLEL RUN CHECKLIST ==="
echo "Start time: $(date)"
echo ""
echo "CHECK AT HOUR 1:"
echo "  [ ] All pods Running in prod namespace"
echo "  [ ] Error rate < 0.1%"
echo "  [ ] p95 latency < 500ms"
echo "  [ ] Replication lag < 50ms"
echo "  [ ] Patroni cluster: 1 Leader, 2 Replicas"
echo ""
echo "CHECK AT HOUR 24:"
echo "  [ ] No pod restarts (memory leaks)"
echo "  [ ] No connection pool exhaustion"
echo "  [ ] Log files not growing unusually large"
echo "  [ ] Database WAL files not accumulating"
echo ""
echo "CHECK AT HOUR 48:"
echo "  [ ] Cron jobs completed successfully"
echo "  [ ] Database size growth rate normal"
echo "  [ ] Backup completed via Veeam"
echo "  [ ] No security alerts"
echo ""
echo "CHECK AT HOUR 72:"
echo "  [ ] All hour-24 and hour-48 checks still passing"
echo "  [ ] Team confident in on-prem stability"
echo "  [ ] SIGN-OFF: Proceed to cutover"
```

### Pre-Cutover Validation Script

```bash
# Run this script on the day of planned cutover (Week 16, Friday afternoon)
# WHY: Last-chance validation before the point of no return

cat > /tmp/pre-cutover-validate.sh << 'EOF'
#!/bin/bash
set -e
FAILURES=0
WARNINGS=0

check() {
  local desc=$1
  local cmd=$2
  local expected=$3
  
  result=$(eval "$cmd" 2>/dev/null)
  if echo "$result" | grep -q "$expected"; then
    echo "✅ $desc"
  else
    echo "❌ FAIL: $desc (got: $result)"
    ((FAILURES++))
  fi
}

warn() {
  local desc=$1
  local cmd=$2
  local threshold=$3
  
  result=$(eval "$cmd" 2>/dev/null)
  if (( $(echo "$result < $threshold" | bc -l) )); then
    echo "✅ $desc: $result"
  else
    echo "⚠️  WARN: $desc: $result (threshold: $threshold)"
    ((WARNINGS++))
  fi
}

echo "=== PRE-CUTOVER VALIDATION $(date) ==="
echo ""

echo "--- KUBERNETES CLUSTER ---"
check "All PROD pods Running" \
  "kubectl get pods -n prod --no-headers | grep -v Running | wc -l" "^0$"
check "All PROD nodes Ready" \
  "kubectl get nodes --selector=environment=prod --no-headers | grep -v Ready | wc -l" "^0$"
check "ArgoCD app synced" \
  "argocd app get prod-application -o json | jq -r '.status.sync.status'" "Synced"

echo ""
echo "--- DATABASE CLUSTER ---"
check "Patroni cluster: has Leader" \
  "patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep Leader | wc -l" "^1$"
check "Patroni cluster: has 2 Replicas" \
  "patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep Replica | wc -l" "^2$"
check "pglogical subscription active" \
  "psql -h 10.30.0.120 -U postgres -d prod_db -t -c \"SELECT status FROM pglogical.show_subscription_status();\" 2>/dev/null" "replicating"

LAG_MS=$(psql -h 10.30.0.120 -U postgres -d prod_db -t -c "
  SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) * 1000;" 2>/dev/null | tr -d ' ')
warn "Replication lag (ms)" "echo ${LAG_MS}" 50

echo ""
echo "--- VEEAM BACKUP ---"
check "Latest backup completed" \
  "veeam_check_backup.sh" "success"  # Implement based on your Veeam setup

echo ""
echo "--- APPLICATION SMOKE TEST ---"
PROD_IP=$(kubectl get svc api-gateway -n prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
check "API health endpoint" \
  "curl -sf http://${PROD_IP}/health | jq -r '.status'" "healthy"
check "Database connected" \
  "curl -sf http://${PROD_IP}/health | jq -r '.database'" "connected"

echo ""
echo "--- NETWORK ---"
check "On-prem DNS resolves" \
  "dig @10.20.0.53 onprem-prod.company.internal +short | wc -l" "[1-9]"

echo ""
echo "========================================"
if [ $FAILURES -eq 0 ]; then
  echo "✅ PRE-CUTOVER VALIDATION PASSED"
  echo "   Failures: ${FAILURES}, Warnings: ${WARNINGS}"
  echo "   READY TO PROCEED WITH CUTOVER"
else
  echo "❌ PRE-CUTOVER VALIDATION FAILED"
  echo "   Failures: ${FAILURES}, Warnings: ${WARNINGS}"
  echo "   DO NOT PROCEED — fix failures first"
  exit 1
fi
EOF

chmod +x /tmp/pre-cutover-validate.sh
/tmp/pre-cutover-validate.sh
```

---

## Week 16: CUTOVER EXECUTION

```
CUTOVER DECISION FLOWCHART
═══════════════════════════════════════════════════════════════════════

  Friday 3:30 PM — Pre-cutover meeting
  ┌─────────────────────────────────────────────────────────────────┐
  │  Run /tmp/pre-cutover-validate.sh                               │
  │  ◆ All checks pass?                                             │
  │    YES → Proceed with cutover at 4:00 PM                        │
  │    NO  → Delay cutover (schedule next Friday window)            │
  └─────────────────────────────────────────────────────────────────┘
                               │ YES
                               ▼
  T+00:00  Friday 4:00 PM — BEGIN CUTOVER
  ┌─────────────────────────────────────────────────────────────────┐
  │  Notify stakeholders: "Cutover starting"                        │
  │  Place maintenance page on Azure (optional for planned)         │
  │  Start recording session for audit trail                        │
  └─────────────────────────────────────────────────────────────────┘
                               │
  T+00:05  Enable Azure maintenance mode (stop new writes)
  ┌─────────────────────────────────────────────────────────────────┐
  │  kubectl scale deployment --replicas=0 --all -n prod (Azure)   │
  │  OR: Azure traffic manager → take Azure endpoint offline         │
  │  Monitor: No new transactions to Azure PostgreSQL               │
  └─────────────────────────────────────────────────────────────────┘
                               │
  T+00:10  Wait for pglogical lag = 0
  ┌─────────────────────────────────────────────────────────────────┐
  │  watch -n 2 'psql -h 10.30.0.120 -U postgres -d prod_db -t -c  │
  │    "SELECT ... pg_last_xact_replay_timestamp()"'                │
  │  Wait until lag = 0ms (Azure and on-prem 100% in sync)          │
  │  ◆ Lag = 0? YES → proceed   NO (> 5 min) → ROLLBACK            │
  └─────────────────────────────────────────────────────────────────┘
                               │ LAG = 0
                               ▼
  T+00:15  Stop pglogical replication (promote on-prem)
  ┌─────────────────────────────────────────────────────────────────┐
  │  psql: SELECT pglogical.drop_subscription('azure_to_onprem_prod')│
  │  On-prem PostgreSQL is now STANDALONE (no longer a subscriber)  │
  │  It accepts ALL write operations                                 │
  └─────────────────────────────────────────────────────────────────┘
                               │
  T+00:20  Switch DNS to on-prem
  ┌─────────────────────────────────────────────────────────────────┐
  │  Update DNS: api.company.com → On-prem MetalLB IP               │
  │  Set TTL=60 (so DNS propagates quickly)                         │
  │  Verify: dig api.company.com → should return on-prem IP         │
  └─────────────────────────────────────────────────────────────────┘
                               │
  T+00:30  Smoke tests & verification
  ┌─────────────────────────────────────────────────────────────────┐
  │  Run full smoke test suite                                      │
  │  Monitor: error rate, latency, database connections             │
  │  ◆ All passing?                                                 │
  │    YES → CUTOVER COMPLETE ✅                                    │
  │    NO (within 30 min) → ROLLBACK (revert DNS + restart Azure)  │
  └─────────────────────────────────────────────────────────────────┘
                               │ COMPLETE
                               ▼
  T+00:30 to T+72:00  HYPERCARE monitoring
  ┌─────────────────────────────────────────────────────────────────┐
  │  24/7 on-call rotation                                          │
  │  Check every 15 minutes for first 24 hours                      │
  │  Grafana dashboards visible on NOC screen                       │
  │  Azure kept on standby (NOT decommissioned) for 2 weeks        │
  └─────────────────────────────────────────────────────────────────┘
```

### Cutover Execution Commands

```bash
# T+00:05 — Stop Azure writes
# (coordinate with Azure team — scale down AKS deployments)
az aks command invoke -g myResourceGroup -n myAKSCluster \
  --command "kubectl scale deployment --all --replicas=0 -n prod"

# T+00:10 — Monitor replication until lag = 0
echo "Waiting for replication lag to reach zero..."
while true; do
  LAG=$(psql -h 10.30.0.120 -U postgres -d prod_db -t -c \
    "SELECT COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) * 1000, 0);" \
    | tr -d ' ')
  echo "$(date) Lag: ${LAG}ms"
  if (( $(echo "$LAG < 5" | bc -l) )); then
    echo "✅ Lag is ${LAG}ms — ready to proceed!"
    break
  fi
  sleep 2
done

# T+00:15 — Drop pglogical subscription (on-prem becomes standalone)
psql -h 10.30.0.120 -U postgres -d prod_db -c \
  "SELECT pglogical.drop_subscription('azure_to_onprem_prod', true);"
echo "✅ On-prem PostgreSQL is now standalone — accepting all writes"

# T+00:20 — Switch DNS
# Update your DNS provider (example using az CLI for Azure DNS)
ONPREM_IP=$(kubectl get svc api-gateway -n prod \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

az network dns record-set a update \
  -g dns-resource-group \
  -z company.com \
  -n api \
  --set "aRecords[0].ipv4Address=${ONPREM_IP}"

echo "✅ DNS updated to ${ONPREM_IP}"
echo "Waiting 60 seconds for DNS propagation..."
sleep 60

# Verify DNS resolved correctly
NEW_IP=$(dig api.company.com +short | head -1)
echo "DNS resolves to: ${NEW_IP}"
[ "${NEW_IP}" = "${ONPREM_IP}" ] && echo "✅ DNS correct" || echo "❌ DNS mismatch!"

# T+00:30 — Final smoke tests
/tmp/pre-cutover-validate.sh
echo ""
echo "🎉 CUTOVER COMPLETE — On-prem PROD is now serving all traffic"
echo "Begin 72-hour hypercare monitoring period"
```

---

## Post-Cutover: 72-Hour Hypercare

### Monitoring Commands for Hypercare

```bash
# Run on the control node — check every 15 minutes for first 24 hours

cat > /tmp/hypercare-check.sh << 'EOF'
#!/bin/bash
echo "=== HYPERCARE CHECK $(date) ==="

# Kubernetes health
echo "--- K8s Pods ---"
kubectl get pods -n prod --no-headers | grep -v Running | grep -v Completed

# Database
echo "--- Database Status ---"
patronictl -c /etc/patroni/patroni.yml list 2>/dev/null | grep -E "Leader|Replica"

# Application metrics (from Prometheus)
echo "--- App Metrics ---"
ERROR_RATE=$(curl -s "http://prometheus:9090/api/v1/query?query=rate(http_requests_total{status=~'5..',namespace='prod'}[5m])" | \
  jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")
echo "Error rate (5xx): ${ERROR_RATE}"

P95_LATENCY=$(curl -s "http://prometheus:9090/api/v1/query?query=histogram_quantile(0.95,rate(http_request_duration_seconds_bucket{namespace='prod'}[5m]))" | \
  jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")
echo "p95 latency: ${P95_LATENCY}s (target: < 0.5s)"

echo ""
echo "If any issues: See 09-Rollback-Procedures.md"
EOF

chmod +x /tmp/hypercare-check.sh

# Schedule hypercare checks
echo "*/15 * * * * root /tmp/hypercare-check.sh >> /var/log/hypercare.log 2>&1" >> /etc/crontab
```

---

## Azure Decommission Schedule

```
AZURE DECOMMISSION PLAN (after successful cutover)
═════════════════════════════════════════════════════

  Week 17-18: Hypercare complete, stable on on-prem
  ├── Keep Azure running as cold standby
  ├── Azure AKS: Scale to 0 (stopped but not deleted)
  └── Azure PostgreSQL: Read-only mode (no new connections)

  Week 19-20: Remove Azure workloads
  ├── Delete AKS workloads (keep AKS cluster 1 week more)
  ├── Remove Azure Load Balancer rules
  └── Update monitoring to remove Azure alerts

  Week 21-24: Azure cleanup
  ├── Delete AKS cluster
  ├── Delete Azure PostgreSQL (after verifying all data in on-prem)
  ├── Delete Container Registry (images in Harbor)
  ├── Delete VNet and associated resources
  └── Cancel Azure subscriptions/services

  Week 25-28: Final cleanup
  ├── Archive Azure infrastructure documentation
  ├── Update disaster recovery plans
  ├── Update runbooks
  └── Final cost savings report
  
  Expected Cost Savings:
  - Azure AKS cluster: ~$3,000/month saved
  - Azure PostgreSQL: ~$800/month saved  
  - Azure Storage/networking: ~$400/month saved
  - Total estimated savings: ~$4,200/month = ~$50,400/year
```

---

## PROD Success Criteria

| Metric | Target | How to Measure |
|--------|--------|----------------|
| API Availability | ≥ 99.9% | Prometheus `up` metric |
| p95 API Latency | < 500ms | `http_request_duration_seconds` |
| Error Rate (5xx) | < 0.1% | `http_requests_total{status=~"5.."}` |
| DB Replication Lag | N/A after cutover | N/A (standalone) |
| Patroni Failover Time | < 30 seconds | Drill test |
| Backup Success | 100% | Veeam job status |
| RTO (Recovery Time) | < 4 hours | DR drill |
| RPO (Recovery Point) | < 15 minutes | Backup frequency |

---

**Previous:** [06-PREPROD-Detailed-Implementation.md](./06-PREPROD-Detailed-Implementation.md)  
**Cutover Details:** [12-Cutover-Runbook.md](./12-Cutover-Runbook.md)  
**Data Migration Details:** [08-Migration-Procedures.md](./08-Migration-Procedures.md)  
**If Something Goes Wrong:** [09-Rollback-Procedures.md](./09-Rollback-Procedures.md)  
**Back to:** [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md)
