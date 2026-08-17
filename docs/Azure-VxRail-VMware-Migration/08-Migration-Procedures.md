# Migration Procedures

**Detailed Data Movement Strategies & Validation**

---

## Data Migration Decision Tree

```
◆ Need zero downtime?
├── YES ──▶ pglogical replication
├── NO, small dataset ──▶ pg_dump / pg_restore
└── Backup/DR copy ──▶ physical snapshot
```

---

## Flowchart 1 — Migration Strategy Selection Tree

```
                    START: Choosing Migration Method
                                  │
                    ◆ Is downtime acceptable?
                    │
          ┌─────YES─┴────NO──────────────────────┐
          │                                       │
          ▼                                       ▼
  ◆ Dataset size?                      pglogical logical replication
  │                                    (continuous, zero-downtime)
  ├── < 10 GB ──▶ pg_dump/restore
  │               (2-4 hrs, low risk)
  │
  ├── 10-100 GB ──▶ ◆ Time window available?
  │                  ├── >4 hrs  ──▶ pg_dump/restore
  │                  └── <4 hrs  ──▶ pglogical
  │
  └── > 100 GB ──▶ Physical snapshot + WAL replay
                   (or pglogical for large PROD)


  MATRIX SUMMARY:
  ┌─────────────┬──────────────────┬─────────────────────────────┐
  │  Phase      │  Method          │  Why                        │
  ├─────────────┼──────────────────┼─────────────────────────────┤
  │  QA          │  pg_dump/restore │  Simple, fast, low risk     │
  │  PREPROD     │  pglogical       │  Test zero-downtime path    │
  │  PROD        │  pglogical       │  Zero downtime required     │
  │  DR copy     │  Physical snap   │  Point-in-time consistency  │
  └─────────────┴──────────────────┴─────────────────────────────┘
```

---

## Flowchart 2 — pg_dump Step-by-Step Flow

```
  ① Connect to Azure PostgreSQL
  ┌──────────────────────────────────────────────────────────┐
  │  psql -h <azure-host> -U <admin> -d postgres             │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ② Set source to read-only (optional)
  ┌──────────────────────────────────────────────────────────┐
  │  ALTER DATABASE <db> SET default_transaction_read_only   │
  │  = on;                                                   │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ③ Run pg_dump
  ┌──────────────────────────────────────────────────────────┐
  │  pg_dump -Fc -j 4 -h <azure> -U <user> <db>             │
  │          -f /backup/<db>.dump                            │
  └────────────────────────┬─────────────────────────────────┘
                           │
                  ◆ Exit code = 0?
                  ├── NO ──▶ Check pg_dump error log
                  │          Re-run with -v flag
                  YES
                           │
  ④ Transfer dump to on-prem
  ┌──────────────────────────────────────────────────────────┐
  │  rsync -avz --progress /backup/<db>.dump                 │
  │        onprem-db:/restore/                               │
  └────────────────────────┬─────────────────────────────────┘
                           │
  ⑤ Restore to on-prem PostgreSQL
  ┌──────────────────────────────────────────────────────────┐
  │  pg_restore -Fc -j 4 -h localhost -U postgres            │
  │             -d <db> /restore/<db>.dump                   │
  └────────────────────────┬─────────────────────────────────┘
                           │
                  ◆ Exit code = 0?
                  ├── NO ──▶ Check errors, fix schema issues
                  YES
                           │
  ⑥ Validate row counts
  ┌──────────────────────────────────────────────────────────┐
  │  psql -c "SELECT schemaname, tablename,                  │
  │            n_live_tup FROM pg_stat_user_tables           │
  │            ORDER BY n_live_tup DESC;"                    │
  └────────────────────────┬─────────────────────────────────┘
                           │
                  ◆ Counts match Azure?
                  ├── NO ──▶ Investigate missing rows
                  YES
                           │
                           ▼
                  ✅ pg_dump migration complete
```

---

## Flowchart 3 — pglogical Setup Flow

```
  ① On Azure (Publisher / Provider side)
  ┌──────────────────────────────────────────────────────────────┐
  │  CREATE EXTENSION pglogical;                                 │
  │  SELECT pglogical.create_node('azure_provider',              │
  │    'host=<azure-host> port=5432 ...');                       │
  │  SELECT pglogical.create_replication_set('migration_set');   │
  │  SELECT pglogical.replication_set_add_all_tables(            │
  │    'migration_set', ARRAY['public']);                        │
  └──────────────────────────────────────────────────────────────┘
                           │
  ② On On-Prem (Subscriber / Receiver side)
  ┌──────────────────────────────────────────────────────────────┐
  │  CREATE EXTENSION pglogical;                                 │
  │  SELECT pglogical.create_node('onprem_subscriber',           │
  │    'host=10.52.100.10 port=5432 ...');                       │
  └──────────────────────────────────────────────────────────────┘
                           │
  ③ Create Subscription (on-prem subscribes to Azure)
  ┌──────────────────────────────────────────────────────────────┐
  │  SELECT pglogical.create_subscription(                       │
  │    subscription_name := 'onprem_sub',                        │
  │    provider_dsn := 'host=<azure> ...',                       │
  │    replication_sets := ARRAY['migration_set']);               │
  └──────────────────────────────────────────────────────────────┘
                           │
  ④ Monitor sync progress
  ┌──────────────────────────────────────────────────────────────┐
  │  SELECT * FROM pglogical.show_subscription_status();         │
  └────────────────────────┬─────────────────────────────────────┘
                           │
                  ◆ Status = 'replicating'?
                  ├── NO ──▶ Check pg_hba, firewall, WAL level
                  YES
                           │
  ⑤ Verify replication lag
  ┌──────────────────────────────────────────────────────────────┐
  │  SELECT now() - pg_last_xact_replay_timestamp() AS lag;      │
  └────────────────────────┬─────────────────────────────────────┘
                           │
                  ◆ Lag < 1 second?
                  ├── NO ──▶ Investigate network / write load
                  YES
                           │
  ⑥ CUTOVER: drop subscription, promote on-prem as primary
  ┌──────────────────────────────────────────────────────────────┐
  │  SELECT pglogical.drop_subscription('onprem_sub');           │
  │  -- On-prem is now authoritative write target                │
  └──────────────────────────────────────────────────────────────┘
                           │
                           ▼
                  ✅ pglogical cutover complete
```

---

## Flowchart 4 — Data Validation Flow

```
  ① Schema validation
  ┌──────────────────────────────────────────────────────────────┐
  │  pg_dump --schema-only azure_db > azure_schema.sql           │
  │  pg_dump --schema-only onprem_db > onprem_schema.sql         │
  │  diff azure_schema.sql onprem_schema.sql                     │
  └────────────────────────┬─────────────────────────────────────┘
                           │
                  ◆ Diff empty?
                  ├── NO ──▶ Apply missing DDL to on-prem
                  YES
                           │
  ② Row count comparison (all tables)
  ┌──────────────────────────────────────────────────────────────┐
  │  SELECT tablename, n_live_tup FROM pg_stat_user_tables       │
  │  -- run on BOTH sides; compare results                       │
  └────────────────────────┬─────────────────────────────────────┘
                           │
                  ◆ All tables match (±0.1%)?
                  ├── NO ──▶ Identify deltas; re-sync or re-dump
                  YES
                           │
  ③ Checksum spot-check (critical tables)
  ┌──────────────────────────────────────────────────────────────┐
  │  SELECT md5(string_agg(t::text,'')) FROM <critical_table> t  │
  │  -- run on BOTH sides; hashes must match                     │
  └────────────────────────┬─────────────────────────────────────┘
                           │
                  ◆ Hashes match?
                  ├── NO ──▶ Row-level diff investigation
                  YES
                           │
  ④ Application smoke tests
  ┌──────────────────────────────────────────────────────────────┐
  │  curl -s https://onprem-api/health  → 200 OK                 │
  │  Run automated test suite against on-prem endpoints          │
  └────────────────────────┬─────────────────────────────────────┘
                           │
                  ◆ All tests pass?
                  ├── NO ──▶ Fix app config / connection strings
                  YES
                           │
                           ▼
                  ✅ Data validation complete — safe to proceed
```


## Table of Contents
1. [Migration Strategy Overview](#migration-strategy-overview)
2. [PostgreSQL Migration Methods](#postgresql-migration-methods)
3. [Application Configuration Migration](#application-configuration-migration)
4. [Secrets & Credentials Migration](#secrets--credentials-migration)
5. [Data Validation & Verification](#data-validation--verification)
6. [Performance Comparison](#performance-comparison)
7. [User Acceptance Testing](#user-acceptance-testing)

---

## Migration Strategy Overview

### Three Migration Paths

**Path 1: pg_dump/pg_restore (QA Phase)**
- Best for: Initial data movement, smaller databases
- Time: 2-4 hours
- Downtime: Yes (read-only during dump)
- Risk: Low

**Path 2: pglogical Logical Replication (PREPROD & PROD)**
- Best for: Continuous replication, zero-downtime cutover
- Time: Initial setup 2-3 hours, ongoing replication hours/days
- Downtime: No (can run in parallel)
- Risk: Medium (monitoring required)

**Path 3: Physical Snapshots (PROD Backup)**
- Best for: Disaster recovery, offline migration
- Time: 1-2 hours
- Downtime: Yes
- Risk: Medium (requires test restore)

---

## PostgreSQL Migration Methods

### Method 1: pg_dump/pg_restore

#### Phase 1: Create Dump from Azure

```bash
# On Azure PostgreSQL or bastion host:
# Connect to Azure Database for PostgreSQL

# Create complete database dump (compressed)
pg_dump -U pguser -h company-server.postgres.database.azure.com \
  --format=custom --compress=9 --verbose \
  --file=/tmp/production_db.dump production_db

# Expected output:
# - Database: production_db
# - Tables: 247
# - Total size: ~650 GB (uncompressed) → ~50 GB (compressed)
# - Time: 2-3 hours

# Generate dump checksum
sha256sum /tmp/production_db.dump > /tmp/production_db.dump.sha256

# Optional: Create separate role/permissions dump
pg_dumpall -U pguser -h company-server.postgres.database.azure.com \
  --roles-only > /tmp/roles.sql

# List dump contents
pg_restore -l /tmp/production_db.dump | head -20
```

#### Phase 2: Transfer Dump to On-Premises

```bash
# Transfer via VPN/ExpressRoute (not internet)
# Method 1: scp
scp -v production_db.dump ops@10.40.0.100:/backup/azure-export/

# Method 2: rsync (resume-able)
rsync -avz --progress production_db.dump ops@10.40.0.100:/backup/azure-export/

# Method 3: Azure Blob Storage (if available)
azcopy copy "https://account.blob.core.windows.net/backups/production_db.dump" \
  "/backup/azure-export/production_db.dump"

# Verify integrity after transfer
sha256sum -c /tmp/production_db.dump.sha256
```

#### Phase 3: Restore to On-Premises PostgreSQL

```bash
# On on-premises PostgreSQL server

# Create database and restore
sudo su - postgres -c "psql -c 'CREATE DATABASE production_db;'"

# Restore with verbose output (to monitor progress)
sudo su - postgres -c "pg_restore -U postgres -d production_db \
  --verbose --jobs=4 --exit-on-error \
  /backup/azure-export/production_db.dump"

# Restore will take: ~2-3 hours (parallel jobs=4 speeds up)

# Restore roles/permissions
sudo su - postgres -c "psql -f /backup/azure-export/roles.sql"

# Verify restoration
sudo su - postgres -c "psql -d production_db -c \
  'SELECT schemaname, COUNT(*) FROM pg_tables GROUP BY schemaname;'"

# Run ANALYZE to update statistics
sudo su - postgres -c "psql -d production_db -c 'ANALYZE;' -v ON_ERROR_STOP=1"
```

#### Phase 4: Validate Restored Database

```bash
# Connect to both Azure and on-prem databases and compare

# Script: compare_databases.sh
#!/bin/bash

AZURE_HOST="company-server.postgres.database.azure.com"
AZURE_USER="pguser@servername"
AZURE_DB="production_db"

ONPREM_HOST="10.30.0.100"
ONPREM_USER="postgres"
ONPREM_DB="production_db"

# Get table list
echo "=== Comparing Tables ==="
pg_dump -U $AZURE_USER -h $AZURE_HOST -d $AZURE_DB --schema-only -t "public.*" | \
  grep "CREATE TABLE" | wc -l

sudo su - postgres -c "psql -h $ONPREM_HOST -U $ONPREM_USER -d $ONPREM_DB" \
  -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public';"

# Compare row counts (critical!)
echo "=== Comparing Row Counts ==="
psql -U $AZURE_USER -h $AZURE_HOST -d $AZURE_DB -t -c \
  "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;" \
  > /tmp/azure_rows.txt

sudo su - postgres -c "psql -h $ONPREM_HOST -U $ONPREM_USER -d $ONPREM_DB -t -c \
  'SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;'" \
  > /tmp/onprem_rows.txt

# Compare files
diff /tmp/azure_rows.txt /tmp/onprem_rows.txt

# If diffs found, investigate and re-restore if needed
```

---

### Method 2: pglogical Logical Replication (Zero-Downtime)

#### Phase 1: Setup pglogical on Both Systems

```bash
# On Azure PostgreSQL:
# Note: Azure PostgreSQL has pglogical pre-installed

# Verify pglogical installed
psql -U pguser -h company.postgres.database.azure.com -d production_db \
  -c "CREATE EXTENSION IF NOT EXISTS pglogical;"

# Create replication slot (for consistency)
psql -U pguser -h company.postgres.database.azure.com -d production_db <<EOF
SELECT pglogical.create_replication_set('default', 
  publish_insert := true,
  publish_update := true,
  publish_delete := true,
  publish_truncate := false
);
EOF

# On On-Premises PostgreSQL:
sudo su - postgres -c "psql -d production_db" <<EOF
CREATE EXTENSION IF NOT EXISTS pglogical;
SELECT pglogical.create_node('onprem_subscriber', 'host=10.30.0.100 port=5432 dbname=production_db user=postgres');
EOF
```

#### Phase 2: Create Publication on Azure (Source)

```bash
# On Azure PostgreSQL

psql -U pguser -h company.postgres.database.azure.com -d production_db <<EOF

-- Create publication for all tables
CREATE PUBLICATION azure_publication FOR ALL TABLES IN SCHEMA public;

-- Or select specific tables only:
-- CREATE PUBLICATION azure_publication FOR TABLE users, orders, products;

-- Verify publication created
SELECT * FROM pg_publication;
SELECT schemaname, tablename FROM pg_publication_tables;

EOF
```

#### Phase 3: Create Subscription on On-Premises (Target)

```bash
# On On-Premises PostgreSQL

sudo su - postgres -c "psql -d production_db" <<EOF

-- Create subscription (starts receiving changes)
CREATE SUBSCRIPTION onprem_subscription
  CONNECTION 'host=company.postgres.database.azure.com port=5432 dbname=production_db user=pguser password=PASSWORD'
  PUBLICATION azure_publication
  WITH (create_slot = false, synchronize_data = true);

-- Monitor subscription status
SELECT * FROM pg_subscription;
SELECT * FROM pg_subscription_rel;

-- Check replication progress
SELECT slot_name, restart_lsn, confirmed_flush_lsn, state FROM pg_replication_slots;

EOF
```

#### Phase 4: Monitor Replication Lag

```bash
# Real-time replication lag monitoring

# On on-prem subscriber:
watch -n 5 "sudo su - postgres -c 'psql -d production_db -c \
  \"SELECT now() - pg_last_wal_receive_time() as replication_lag, state FROM pg_subscription_stat;\"'"

# Expected: Replication lag should be < 50ms and decreasing

# Application can read from on-prem (read replicas)
# Writes still go to Azure (primary)

# After 2-3 weeks of stable replication, proceed to cutover
```

---

## Application Configuration Migration

### Database Connection String Migration

```bash
# Update application configuration (Kubernetes ConfigMap/Secret)

# Current (Azure):
DATABASE_URL="postgresql://user:pass@company.postgres.database.azure.com:5432/production_db"

# Target (On-Prem Patroni VIP):
DATABASE_URL="postgresql://user:pass@10.30.0.10:5432/production_db"

# Update ConfigMap
kubectl create configmap app-config \
  --from-literal=DATABASE_URL="postgresql://user:pass@10.30.0.10:5432/production_db" \
  -n prod --dry-run=client -o yaml | kubectl apply -f -

# Rolling restart to pick up new config
kubectl rollout restart deployment/api-gateway -n prod
```

### Container Registry Migration (Harbor)

```bash
# Migrate images from ACR to Harbor

# List all images in ACR
az acr repository list --name company-acr --output table

# Pull each image from ACR
docker pull company-acr.azurecr.io/namespace/app-gateway:1.0.0

# Tag for Harbor
docker tag company-acr.azurecr.io/namespace/app-gateway:1.0.0 \
  harbor.internal/prod/app-gateway:1.0.0

# Push to Harbor
docker push harbor.internal/prod/app-gateway:1.0.0

# Update image pull secrets in Kubernetes
kubectl create secret docker-registry harbor-cred \
  --docker-server=harbor.internal \
  --docker-username=username \
  --docker-password=password \
  -n prod --dry-run=client -o yaml | kubectl apply -f -

# Update deployment to use Harbor registry
kubectl patch deployment api-gateway -n prod \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"app-gateway","image":"harbor.internal/prod/app-gateway:1.0.0"}]}}}}'
```

---

## Secrets & Credentials Migration

### Azure Key Vault to On-Premises Vault

```bash
# Export secrets from Azure Key Vault
az keyvault secret list --vault-name company-vault --query "[].name"

# For each secret:
az keyvault secret show --vault-name company-vault --name db-password \
  --query "value" -o tsv > /tmp/db-password.txt

# Transfer securely to on-premises
# Use VPN/encrypted channels (not unencrypted)

# Import to HashiCorp Vault or similar
vault kv put secret/production/database password=<value>

# Update Kubernetes secrets
kubectl create secret generic db-credentials \
  --from-literal=username=postgres \
  --from-literal=password=<password> \
  -n prod --dry-run=client -o yaml | kubectl apply -f -

# Verify secrets mounted in pods
kubectl get secrets -n prod
kubectl describe pod <pod-name> -n prod | grep -A 5 "Mounts:"
```

---

## Data Validation & Verification

### Pre-Migration Validation

```bash
# 1. Database size check
SELECT pg_size_pretty(pg_database_size('production_db'));
# Expected: ~650 GB

# 2. Table count
SELECT COUNT(*) FROM pg_tables WHERE schemaname='public';
# Expected: 247 tables

# 3. Index count
SELECT COUNT(*) FROM pg_indexes WHERE schemaname='public';
# Expected: 1,200+ indexes

# 4. Constraint check
SELECT COUNT(*) FROM pg_constraint WHERE contype IN ('p','u','f','c');
# Expected: All constraints present

# 5. View/Function count
SELECT COUNT(*) FROM pg_views WHERE schemaname='public';
SELECT COUNT(*) FROM pg_proc WHERE pronamespace > 2200;
```

### Post-Migration Validation

```bash
# 1. Restore verification (row counts match)
AZURE_COUNT=$(psql -U pguser -h azure.host -d production_db -t -c \
  "SELECT COUNT(*) FROM users;")
ONPREM_COUNT=$(psql -h 10.30.0.100 -U postgres -d production_db -t -c \
  "SELECT COUNT(*) FROM users;")

if [ "$AZURE_COUNT" = "$ONPREM_COUNT" ]; then
  echo "✓ Row counts match: $AZURE_COUNT rows"
else
  echo "✗ Row count mismatch! Azure: $AZURE_COUNT, On-Prem: $ONPREM_COUNT"
fi

# 2. Data integrity checks
-- No NULL primary keys
SELECT COUNT(*) FROM users WHERE user_id IS NULL;  -- Should be 0

-- No orphaned foreign keys
SELECT COUNT(*) FROM orders o WHERE NOT EXISTS (
  SELECT 1 FROM users u WHERE u.user_id = o.user_id
);  -- Should be 0

# 3. Checksum comparison (for critical tables)
SELECT md5(string_agg(users::text, '')) FROM users ORDER BY user_id;
# Compare on both systems
```

---

## Performance Comparison

### Pre vs Post Migration Performance

```bash
# Run same queries on Azure and On-Prem

# Test 1: Simple select
QUERY="SELECT COUNT(*) FROM orders WHERE user_id = 1;"

TIME_AZURE=$(psql -U pguser -h azure.host -d production_db --timing -c "$QUERY" 2>&1 | grep "Time")
TIME_ONPREM=$(psql -h 10.30.0.100 -U postgres -d production_db --timing -c "$QUERY" 2>&1 | grep "Time")

echo "Azure: $TIME_AZURE"
echo "On-Prem: $TIME_ONPREM"

# Test 2: Complex join (production query)
COMPLEX_QUERY="SELECT u.name, COUNT(o.order_id) as order_count FROM users u 
  LEFT JOIN orders o ON u.user_id = o.user_id 
  WHERE u.created_at > NOW() - INTERVAL '30 days'
  GROUP BY u.user_id, u.name ORDER BY order_count DESC;"

# Expected: On-prem should be < 500ms (same or faster than Azure)
```

---

## User Acceptance Testing (UAT)

### UAT Checklist

```bash
# UAT Phase (1-2 weeks post-cutover)

- [ ] Users can login to application
- [ ] API endpoints responding correctly
- [ ] Database queries return expected results
- [ ] File uploads working to on-prem storage
- [ ] Email notifications being sent
- [ ] Payment processing functional
- [ ] Analytics data being collected
- [ ] Scheduled jobs running on time
- [ ] Backups completing successfully
- [ ] Monitoring alerts firing correctly

# Issues found during UAT:
# 1. Document issue
# 2. Root cause analysis
# 3. Fix applied
# 4. Verify fix
# 5. Update runbook for future reference
```

---

**Reference**: [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md), [07-PROD-Detailed-Implementation.md](./07-PROD-Detailed-Implementation.md), [09-Rollback-Procedures.md](./09-Rollback-Procedures.md)

