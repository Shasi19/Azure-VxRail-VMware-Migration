# PREPROD Migration Plan

**Environment: PREPROD | Weeks 4–8 | Azure → On-Premises VxRail**

---

## Migration Flowchart

```
PREPROD MIGRATION FLOW
══════════════════════════════════════════════════════════════════════

  AZURE PREPROD                        ON-PREMISES VxRail
  ─────────────────                    ──────────────────────────────

  ┌─────────────────┐
  │  Azure PostgreSQL│
  │  preprod_db      │
  │  (source DB)     │
  └────────┬────────┘
           │ pg_dump (Step 1)
           │ ~30–60 min
           ▼
  ┌─────────────────┐
  │  .dump file      │  ──── secure copy ────▶  ┌──────────────────────┐
  │  preprod_db.dump │       (scp / AzCopy)      │  pg-preprod-01       │
  └─────────────────┘       ~10–30 min           │  Patroni Leader      │
                                                  │  10.30.0.110         │
                                                  └──────────┬───────────┘
                                                             │ pg_restore (Step 2)
                                                             │ ~20–90 min
                                                             ▼
                                                  ┌──────────────────────┐
                                                  │  preprod_db restored │
                                                  │  on Patroni Leader   │
                                                  └──────────┬───────────┘
                                                             │ Patroni WAL replication
                                                             │ auto-syncs replicas
                                                             ▼
                                          ┌──────────────────────────────────────┐
                                          │  Patroni HA Cluster                  │
                                          │  pg-preprod-01 (Leader)  10.30.0.110 │
                                          │  pg-preprod-02 (Replica) 10.30.0.111 │
                                          │  pg-preprod-03 (Replica) 10.30.0.112 │
                                          │  lag_in_MB = 0 on all replicas       │
                                          └──────────┬───────────────────────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────────┐
                                          │  pgBouncer           │
                                          │  VIP 10.30.0.100     │
                                          │  port 5432           │
                                          └──────────┬───────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────────┐
                                          │  Validate DB Restore  │
                                          │  Row-count checks     │
                                          │  Replication lag = 0  │
                                          └──────────┬───────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────────┐
                                          │  Harbor Image Verify  │
                                          │  Secrets + Namespace  │
                                          └──────────┬───────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────────┐
                                          │  ArgoCD Deploy        │
                                          │  preprod branch       │
                                          │  3 replicas per app   │
                                          └──────────┬───────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────────┐
                                          │  Smoke Tests          │
                                          │  pgBouncer pool check │
                                          └──────────┬───────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────────┐
                                          │  Load Test Gate       │
                                          │  k6: up to 3000 users │
                                          │  p95 < 500ms          │
                                          └──────────┬───────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────────┐
                                          │  Patroni Failover     │
                                          │  Validation Test      │
                                          └──────────┬───────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────────┐
                                          │  PREPROD SIGN-OFF     │
                                          │  ✅ Migration Complete │
                                          └──────────────────────┘
```

---

## Pre-Migration Checklist

- [ ] PREPROD workbook baseline reconciled: 2 x Standard D2s v4 AKS nodes ($189/month), PostgreSQL ($719/month), and Cosmos DB ($132/month).
- [ ] Selected Kubernetes platform, version, CNI, CSI, ingress, and backup support matrix approved.
- [ ] Database PITR restore and Patroni failover have both passed before load testing.
- [ ] No credentials are embedded in scripts or committed to Git.

- [ ] PREPROD K8s cluster: 12 nodes in `Ready` state (`kubectl get nodes`)
- [ ] Patroni cluster running: 1 Leader + 2 Replicas (`patronictl -c /etc/patroni/patroni.yml list`)
- [ ] pgBouncer VIP `10.30.0.100` responding (`psql -h 10.30.0.100 -U app_user -c "SELECT 1"`)
- [ ] Harbor images from QA migration still available and tagged correctly
- [ ] ArgoCD connected to `preprod` branch and application CRDs present
- [ ] Azure PREPROD credentials and Key Vault access confirmed (`az keyvault secret show ...`)
- [ ] PREPROD dump directory has sufficient disk space (≥ 2× DB size): `df -h /mnt/migration`
- [ ] Network connectivity from jump host to `10.30.0.110` port 5432 confirmed
- [ ] Notification sent to stakeholders (email + Slack `#migration-preprod`)

---

## Step 1: Export PREPROD Database from Azure

**Timing estimate:** PREPROD database is typically larger than QA (potentially 20–100 GB depending on data volume). Expect `pg_dump` to take **30–90 minutes**. Run inside a `tmux` or `screen` session.

### 1.1 Set environment variables

```bash
export AZURE_PG_HOST="preprod-pg.postgres.database.azure.com"
export AZURE_PG_USER="pgadmin@preprod-pg"
export AZURE_PG_DB="preprod_db"
export DUMP_DIR="/mnt/migration/preprod"
export DUMP_FILE="${DUMP_DIR}/preprod_db_$(date +%Y%m%d_%H%M%S).dump"

mkdir -p "${DUMP_DIR}"
```

### 1.2 Run pg_dump in custom format (parallel-capable, fastest restore)

```bash
time pg_dump \
  --host="${AZURE_PG_HOST}" \
  --port=5432 \
  --username="${AZURE_PG_USER}" \
  --dbname="${AZURE_PG_DB}" \
  --format=custom \
  --compress=6 \
  --jobs=4 \
  --verbose \
  --no-password \
  --file="${DUMP_FILE}"
```

> **Note:** `--jobs=4` requires `--format=directory`. If using `--format=custom`, omit `--jobs` (custom format is single-threaded). For very large PREPROD databases, switch to `--format=directory` and a parallel restore:
> ```bash
> pg_dump ... --format=directory --jobs=4 --file="${DUMP_DIR}/preprod_dump_dir/"
> ```

### 1.3 Verify dump integrity

```bash
pg_restore --list "${DUMP_FILE}" | head -20
ls -lh "${DUMP_FILE}"
```

### 1.4 Transfer dump to on-premises pg-preprod-01

```bash
# Using scp (adjust key path as needed)
scp -i ~/.ssh/migration_key \
  "${DUMP_FILE}" \
  postgres@10.30.0.110:/var/lib/postgresql/migration/

# Verify transfer checksum
md5sum "${DUMP_FILE}"
ssh postgres@10.30.0.110 "md5sum /var/lib/postgresql/migration/$(basename ${DUMP_FILE})"
```

> **Timing:** Transfer of a 20 GB file over a 1 Gbps link takes ~3 minutes; 100 GB takes ~15 minutes. For large databases, consider using `azcopy` or `rsync -z` for resumable transfers.

---

## Step 2: Restore to Patroni HA Cluster

**Target:** Patroni Leader `pg-preprod-01` at `10.30.0.110`

> ⚠️ **Important:** Always restore to the **Patroni Leader** only. Patroni streaming replication will automatically sync the replicas after restore. Do not restore directly to replicas.

### 2.1 Create the target database on the Leader

```bash
ssh postgres@10.30.0.110

# Confirm this node is the Patroni Leader
patronictl -c /etc/patroni/patroni.yml list

# Create empty target database
psql -U postgres -c "CREATE DATABASE preprod_db OWNER app_user;"
```

### 2.2 Run pg_restore

```bash
DUMP_FILE="/var/lib/postgresql/migration/preprod_db_<timestamp>.dump"

time pg_restore \
  --host=127.0.0.1 \
  --port=5432 \
  --username=postgres \
  --dbname=preprod_db \
  --format=custom \
  --jobs=4 \
  --verbose \
  --no-password \
  "${DUMP_FILE}"
```

> **Timing estimate:** 20 GB dump restores in ~15–30 min; 100 GB may take 1–2 hours. Monitor with:
> ```bash
> watch -n 5 "psql -U postgres -c \"SELECT schemaname, relname, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 10;\""
> ```

### 2.3 Wait for Patroni replication to sync

After restore, Patroni automatically begins streaming WAL to replicas. Wait for replication to catch up:

```bash
# Check lag every 30 seconds until lag_in_MB = 0 on all replicas
watch -n 30 "patronictl -c /etc/patroni/patroni.yml list"
```

Expected output when synced:

```
+ Cluster: preprod-cluster ----+----+-----------+
| Member        | Host          | Role    | State   | TL | Lag in MB |
+---------------+---------------+---------+---------+----+-----------+
| pg-preprod-01 | 10.30.0.110:5432 | Leader  | running |  1 |           |
| pg-preprod-02 | 10.30.0.111:5432 | Replica | running |  1 |         0 |
| pg-preprod-03 | 10.30.0.112:5432 | Replica | running |  1 |         0 |
+---------------+---------------+---------+---------+----+-----------+
```

---

## Step 3: Validate DB Restore + Replication

### 3.1 Row-count validation (same script as QA)

```bash
#!/bin/bash
# validate-preprod-db.sh
AZURE_HOST="preprod-pg.postgres.database.azure.com"
ONPREM_HOST="10.30.0.110"
DB="preprod_db"
PG_USER="postgres"
MISMATCH=0

TABLES=$(psql -h ${ONPREM_HOST} -U ${PG_USER} -d ${DB} -t -c \
  "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;")

echo "=== Row Count Validation: PREPROD ==="
printf "%-40s %-15s %-15s %-10s\n" "TABLE" "AZURE" "ON-PREM" "STATUS"
printf "%-40s %-15s %-15s %-10s\n" "-----" "-----" "-------" "------"

for TABLE in ${TABLES}; do
  AZURE_COUNT=$(psql -h ${AZURE_HOST} -U ${PG_USER} -d ${DB} -t -c \
    "SELECT COUNT(*) FROM ${TABLE};" | tr -d ' ')
  ONPREM_COUNT=$(psql -h ${ONPREM_HOST} -U ${PG_USER} -d ${DB} -t -c \
    "SELECT COUNT(*) FROM ${TABLE};" | tr -d ' ')

  if [ "${AZURE_COUNT}" = "${ONPREM_COUNT}" ]; then
    STATUS="✅ OK"
  else
    STATUS="❌ MISMATCH"
    MISMATCH=1
  fi
  printf "%-40s %-15s %-15s %-10s\n" "${TABLE}" "${AZURE_COUNT}" "${ONPREM_COUNT}" "${STATUS}"
done

echo ""
if [ ${MISMATCH} -eq 0 ]; then
  echo "✅ All row counts match. DB restore validated."
else
  echo "❌ Row count mismatches detected. DO NOT PROCEED."
  exit 1
fi
```

```bash
chmod +x validate-preprod-db.sh
./validate-preprod-db.sh
```

### 3.2 Validate replication lag (PREPROD-specific)

```bash
psql -h 10.30.0.110 -U postgres -c "
SELECT
  client_addr,
  state,
  sync_state,
  write_lag,
  flush_lag,
  replay_lag,
  pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication
ORDER BY client_addr;"
```

**Expected output (healthy):**

```
  client_addr  |   state   | sync_state | write_lag | flush_lag | replay_lag | lag_bytes
---------------+-----------+------------+-----------+-----------+------------+-----------
 10.30.0.111   | streaming | async      | 00:00:00  | 00:00:00  | 00:00:00   |         0
 10.30.0.112   | streaming | async      | 00:00:00  | 00:00:00  | 00:00:00   |         0
```

> ⚠️ Do **not** proceed to Step 4 if `lag_bytes > 0` after 10 minutes of idle time.

### 3.3 Validate sequences and constraints

```bash
psql -h 10.30.0.110 -U postgres -d preprod_db -c "
SELECT schemaname, sequencename, last_value
FROM pg_sequences
ORDER BY schemaname, sequencename;"

# Check for invalid constraints or indexes
psql -h 10.30.0.110 -U postgres -d preprod_db -c "
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;" | head -30
```

---

## Step 4: Migrate Images and Secrets

### 4.1 Verify Harbor images (from QA migration)

```bash
# List available images — these should already exist from QA migration
curl -s -u admin:${HARBOR_PASSWORD} \
  https://harbor.internal/api/v2.0/projects/preprod/repositories \
  | jq '.[].name'

# Verify specific service images exist with expected tags
for IMAGE in api-service worker-service frontend-service; do
  echo "Checking: ${IMAGE}"
  curl -s -u admin:${HARBOR_PASSWORD} \
    "https://harbor.internal/api/v2.0/projects/preprod/repositories/${IMAGE}/artifacts" \
    | jq '.[0].tags[].name'
done
```

> If images are missing, re-tag from QA:
> ```bash
> docker pull harbor.internal/qa/${IMAGE}:latest
> docker tag harbor.internal/qa/${IMAGE}:latest harbor.internal/preprod/${IMAGE}:latest
> docker push harbor.internal/preprod/${IMAGE}:latest
> ```

### 4.2 Create PREPROD namespace and secrets

```bash
# Create namespace
kubectl create namespace preprod --dry-run=client -o yaml | kubectl apply -f -

# Retrieve PREPROD-specific DB password from Azure Key Vault
export PREPROD_DB_PASSWORD=$(az keyvault secret show \
  --vault-name "preprod-keyvault" \
  --name "preprod-db-password" \
  --query "value" -o tsv)

# Create DB credentials secret (PREPROD password — different from QA)
kubectl create secret generic preprod-db-credentials \
  --namespace=preprod \
  --from-literal=host=10.30.0.100 \
  --from-literal=port=5432 \
  --from-literal=database=preprod_db \
  --from-literal=username=app_user \
  --from-literal=password="${PREPROD_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create other PREPROD secrets (API keys, third-party credentials)
kubectl create secret generic preprod-app-secrets \
  --namespace=preprod \
  --from-literal=api-key="${PREPROD_API_KEY}" \
  --from-literal=redis-url="redis://10.30.0.200:6379/1" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 4.3 Verify secrets are set correctly

```bash
kubectl get secrets -n preprod
kubectl describe secret preprod-db-credentials -n preprod
```

---

## Step 5: Deploy Applications

### 5.1 Configure ArgoCD for preprod branch

```bash
# Verify ArgoCD is connected to preprod branch
argocd app list | grep preprod

# If application not yet registered:
argocd app create preprod-app \
  --repo https://github.com/org/app-manifests.git \
  --path k8s/preprod \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace preprod \
  --revision preprod \
  --sync-policy automated \
  --self-heal

# Trigger sync
argocd app sync preprod-app --timeout 300
```

### 5.2 Monitor rollout

```bash
# Watch all deployments roll out in preprod namespace
kubectl rollout status deployment -n preprod --timeout=600s

# Verify replica counts (PREPROD uses 3 replicas vs QA's 1)
kubectl get deployments -n preprod
```

Expected output:

```
NAME               READY   UP-TO-DATE   AVAILABLE
api-service        3/3     3            3
worker-service     3/3     3            3
frontend-service   3/3     3            3
```

### 5.3 Check pod logs for startup errors

```bash
kubectl logs -n preprod -l app=api-service --tail=50
kubectl logs -n preprod -l app=worker-service --tail=50
```

---

## Step 6: Smoke Tests

### 6.1 Basic connectivity

```bash
# MetalLB PREPROD IP — update with actual IP from MetalLB pool
export PREPROD_LB_IP="10.30.1.50"

# Health check
curl -sf http://${PREPROD_LB_IP}/health | jq .

# API smoke tests
curl -sf http://${PREPROD_LB_IP}/api/v1/status | jq .
curl -sf -X POST http://${PREPROD_LB_IP}/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"preprod_test_user","password":"testpassword"}' | jq .
```

### 6.2 pgBouncer connection pooling verification

```bash
# Connect to pgBouncer admin interface
psql -h 10.30.0.100 -p 6432 -U pgbouncer pgbouncer -c "SHOW STATS;"
psql -h 10.30.0.100 -p 6432 -U pgbouncer pgbouncer -c "SHOW POOLS;"
psql -h 10.30.0.100 -p 6432 -U pgbouncer pgbouncer -c "SHOW CLIENTS;"
```

Expected `SHOW POOLS` output (healthy):

```
 database  |   user    | cl_active | cl_waiting | sv_active | sv_idle | sv_used | maxwait
-----------+-----------+-----------+------------+-----------+---------+---------+---------
 preprod_db| app_user  |        12 |          0 |        12 |       8 |       0 |       0
```

> ⚠️ `cl_waiting > 0` means the connection pool is exhausted. Increase `max_client_conn` in pgBouncer config if seen under normal load.

### 6.3 Database round-trip test through pgBouncer

```bash
# Verify writes route through pgBouncer → Patroni Leader
psql -h 10.30.0.100 -U app_user -d preprod_db -c "
INSERT INTO migration_test (env, tested_at, status)
VALUES ('preprod', NOW(), 'smoke_test')
RETURNING *;"

# Verify reads from replicas (set target_session_attrs for read-only routing)
psql -h 10.30.0.100 -U app_user -d preprod_db \
  "target_session_attrs=any" -c "
SELECT env, tested_at, status FROM migration_test
WHERE env = 'preprod'
ORDER BY tested_at DESC LIMIT 5;"
```

---

## Step 7: Load Test Gate

### 7.1 k6 load test script

```javascript
// preprod-load-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const dbLatency = new Trend('db_query_latency');

export const options = {
  stages: [
    { duration: '2m',  target: 100  },  // ramp to 100 users
    { duration: '3m',  target: 100  },  // hold at 100 (baseline)
    { duration: '2m',  target: 500  },  // ramp to 500
    { duration: '3m',  target: 500  },  // hold at 500
    { duration: '2m',  target: 1000 },  // ramp to 1000
    { duration: '3m',  target: 1000 },  // hold at 1000
    { duration: '2m',  target: 2000 },  // ramp to 2000
    { duration: '3m',  target: 2000 },  // hold at 2000
    { duration: '2m',  target: 3000 },  // ramp to 3000 (peak)
    { duration: '5m',  target: 3000 },  // hold at 3000
    { duration: '3m',  target: 0    },  // ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],   // p95 < 500ms
    errors:            ['rate<0.001'],  // error rate < 0.1%
    http_req_failed:   ['rate<0.001'],
  },
};

const BASE_URL = `http://${__ENV.PREPROD_LB_IP}`;

export default function () {
  // Read-heavy endpoint (tests pgBouncer + Patroni replica routing)
  const listRes = http.get(`${BASE_URL}/api/v1/items?page=1&limit=20`);
  check(listRes, {
    'list status 200': (r) => r.status === 200,
    'list latency < 300ms': (r) => r.timings.duration < 300,
  });
  errorRate.add(listRes.status !== 200);

  // Write endpoint (tests pgBouncer → Patroni Leader)
  const createRes = http.post(
    `${BASE_URL}/api/v1/items`,
    JSON.stringify({ name: `load-test-item-${Date.now()}`, env: 'preprod' }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(createRes, {
    'create status 201': (r) => r.status === 201,
    'create latency < 500ms': (r) => r.timings.duration < 500,
  });
  errorRate.add(createRes.status !== 201);

  sleep(1);
}
```

### 7.2 Run load test

```bash
export PREPROD_LB_IP="10.30.1.50"

k6 run \
  --out influxdb=http://influxdb.monitoring:8086/k6 \
  -e PREPROD_LB_IP="${PREPROD_LB_IP}" \
  preprod-load-test.js
```

### 7.3 Monitor replication lag during load test

```bash
# Run in parallel terminal during k6 test
watch -n 5 "psql -h 10.30.0.110 -U postgres -c \"
SELECT client_addr,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes,
       replay_lag
FROM pg_stat_replication;\""
```

### 7.4 Pass criteria

| Metric | Threshold | Action if Failed |
|--------|-----------|-----------------|
| p95 response time | < 500ms | Scale up replicas or tune `max_connections` |
| Error rate | < 0.1% | Check application logs and DB connection pool |
| DB replication lag | < 100ms under load | Tune `wal_level`, `synchronous_commit`, or scale Patroni replicas |
| pgBouncer `cl_waiting` | 0 at steady state | Increase `max_client_conn` and `pool_size` in pgBouncer |

### 7.5 Performance tuning if thresholds fail

**If p95 > 500ms:**
```bash
# Check slow queries
psql -h 10.30.0.110 -U postgres -d preprod_db -c "
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC LIMIT 10;"

# Add missing indexes
psql -h 10.30.0.110 -U postgres -d preprod_db -c "
SELECT relname, seq_scan, idx_scan, seq_tup_read
FROM pg_stat_user_tables
WHERE seq_scan > idx_scan AND n_live_tup > 10000
ORDER BY seq_scan DESC;"
```

**If replication lag > 100ms:**
```bash
# Check WAL sender status on primary
psql -h 10.30.0.110 -U postgres -c "
SELECT pid, application_name, state, sent_lsn, write_lsn, flush_lsn, replay_lsn
FROM pg_stat_replication;"

# Tune wal_buffers if needed (requires restart via Patroni)
patronictl -c /etc/patroni/patroni.yml edit-config
# Set: wal_buffers: 64MB, checkpoint_completion_target: 0.9
```

**If pgBouncer pool exhausted:**
```bash
# Edit pgBouncer config on all pgBouncer nodes
sudo vi /etc/pgbouncer/pgbouncer.ini
# Increase: max_client_conn = 1000, default_pool_size = 50
sudo systemctl reload pgbouncer
```

---

## Step 8: Patroni Failover Test as Part of Migration Validation

> ⚠️ **This step is mandatory before PREPROD sign-off.** It validates that the application handles database leader failover gracefully and that Patroni promotes a replica without data loss.

### 8.1 Pre-failover state capture

```bash
# Confirm cluster state before test
patronictl -c /etc/patroni/patroni.yml list

# Note the current leader
export PRIMARY_NODE="pg-preprod-01"
export REPLICA_1="pg-preprod-02"

# Check app is serving traffic
curl -sf http://10.30.1.50/health | jq .status
```

### 8.2 Simulate primary failure

```bash
# Method 1: Patroni-managed switchover (graceful, preferred for testing)
patronictl -c /etc/patroni/patroni.yml switchover preprod-cluster \
  --master pg-preprod-01 \
  --candidate pg-preprod-02 \
  --force

# Method 2: Kill PostgreSQL process on primary (simulates hard failure)
# ssh postgres@10.30.0.110 "sudo systemctl stop patroni"
```

### 8.3 Monitor promotion

```bash
# Watch cluster — pg-preprod-02 should become Leader within 15–30 seconds
watch -n 2 "patronictl -c /etc/patroni/patroni.yml list"
```

Expected outcome after failover:

```
+ Cluster: preprod-cluster ----+----+-----------+
| Member        | Host          | Role    | State   | TL | Lag in MB |
+---------------+---------------+---------+---------+----+-----------+
| pg-preprod-01 | 10.30.0.110:5432 | Replica | running |  2 |         0 |
| pg-preprod-02 | 10.30.0.111:5432 | Leader  | running |  2 |           |
| pg-preprod-03 | 10.30.0.112:5432 | Replica | running |  2 |         0 |
+---------------+---------------+---------+---------+----+-----------+
```

> ⚠️ Timeline: `TL` (timeline) increments from 1 → 2 on successful promotion.

### 8.4 Verify application reconnects automatically

```bash
# pgBouncer should reconnect to new Leader automatically via Patroni DNS/VIP
# Wait 10–15 seconds, then test
sleep 15
curl -sf http://10.30.1.50/api/v1/health | jq .

# Confirm writes reach new leader
psql -h 10.30.0.100 -U app_user -d preprod_db -c "
INSERT INTO migration_test (env, tested_at, status)
VALUES ('preprod', NOW(), 'post_failover_write')
RETURNING *;"
```

### 8.5 Restore original topology (optional)

```bash
# Switchback to original primary if needed
patronictl -c /etc/patroni/patroni.yml switchover preprod-cluster \
  --master pg-preprod-02 \
  --candidate pg-preprod-01 \
  --force
```

### 8.6 Failover test pass criteria

| Check | Expected Result |
|-------|----------------|
| Promotion time | < 30 seconds |
| App reconnect time | < 15 seconds (pgBouncer reconnect) |
| Data loss | 0 rows lost |
| Timeline increment | TL increments by 1 |
| Replica sync after failover | lag_in_MB = 0 within 2 minutes |

---

## Rollback Plan

> **Note:** PREPROD has no user-facing DNS cutover. All traffic is internal. Rollback risk is low, but the following procedures apply if the migration needs to be reversed.

### Rollback Scenario 1: DB restore failed or validation failed

```bash
# Drop the partially restored database
psql -h 10.30.0.110 -U postgres -c "DROP DATABASE IF EXISTS preprod_db;"

# Reinstate Azure PREPROD as the connection target in app config
kubectl delete secret preprod-db-credentials -n preprod
kubectl create secret generic preprod-db-credentials \
  --namespace=preprod \
  --from-literal=host=preprod-pg.postgres.database.azure.com \
  --from-literal=database=preprod_db \
  --from-literal=username="${AZURE_PG_USER}" \
  --from-literal=password="${AZURE_PG_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart app pods to pick up new secret
kubectl rollout restart deployment -n preprod
```

### Rollback Scenario 2: Reset Patroni cluster after bad state

```bash
# Stop Patroni on all nodes
for NODE in 10.30.0.110 10.30.0.111 10.30.0.112; do
  ssh postgres@${NODE} "sudo systemctl stop patroni"
done

# Remove DCS (etcd/consul) cluster data — this forces a clean re-initialization
# ⚠️ Only do this if you intend to fully reinitialize the cluster
patronictl -c /etc/patroni/patroni.yml remove preprod-cluster

# Reinitialize from the designated primary
ssh postgres@10.30.0.110 "sudo systemctl start patroni"

# Wait for primary to be ready, then start replicas
sleep 10
for NODE in 10.30.0.111 10.30.0.112; do
  ssh postgres@${NODE} "sudo systemctl start patroni"
done

# Verify cluster re-formed
patronictl -c /etc/patroni/patroni.yml list
```

### Rollback Scenario 3: Application issues after deploy

```bash
# Roll back ArgoCD to previous revision
argocd app rollback preprod-app

# Or manually roll back specific deployments
kubectl rollout undo deployment/api-service -n preprod
kubectl rollout undo deployment/worker-service -n preprod
kubectl rollout status deployment -n preprod
```

---

## PREPROD Migration Sign-Off

| # | Validation Item | Expected Result | Actual Result | Status | Verified By | Date |
|---|-----------------|----------------|---------------|--------|-------------|------|
| 1 | K8s cluster: 12 nodes Ready | All nodes `Ready` | | ☐ | | |
| 2 | DB dump checksum match | MD5 matches source | | ☐ | | |
| 3 | Row count validation script | All tables ✅ OK | | ☐ | | |
| 4 | Patroni replication lag | `lag_in_MB = 0` on all replicas | | ☐ | | |
| 5 | pgBouncer VIP responding | `SELECT 1` returns via `10.30.0.100` | | ☐ | | |
| 6 | ArgoCD deploy: 3 replicas per service | All deployments `3/3 Ready` | | ☐ | | |
| 7 | Smoke tests passed | All endpoints HTTP 200 | | ☐ | | |
| 8 | pgBouncer pool check | `cl_waiting = 0` at idle | | ☐ | | |
| 9 | Load test: p95 < 500ms at 3000 users | p95 ≤ 500ms | | ☐ | | |
| 10 | Load test: error rate < 0.1% | Error rate ≤ 0.1% | | ☐ | | |
| 11 | Load test: DB lag < 100ms | Lag ≤ 100ms under load | | ☐ | | |
| 12 | Patroni failover test | Promotion < 30s, zero data loss | | ☐ | | |
| 13 | App reconnects after failover | Reconnect < 15s | | ☐ | | |

**PREPROD Migration Approved By:**

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Migration Lead | | | |
| QA Lead | | | |
| Infrastructure Lead | | | |
| Application Owner | | | |

> **Gate:** All 13 items must be ✅ before PROD migration (Doc 17) may begin.
