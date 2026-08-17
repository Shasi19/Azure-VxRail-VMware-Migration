# Disaster Recovery Strategy

**RTO/RPO Targets, Backup Architecture & DR Testing**

---

## DR Failover Flowchart

```
┌──────────────┐
│ Incident     │
└──────┬───────┘
       ▼
┌──────────────┐
│ Assess RTO   │
└──────┬───────┘
       ▼
◆ Recover local? ──YES──▶ Restore service
       │
       NO
       ▼
  Fail over to DR workflow
```

---

## Flowchart 1 — DR Architecture Topology

```
╔══════════════════════════════════════════════════════════════════╗
║                PRIMARY SITE — VxRail On-Premises                ║
║                                                                  ║
║  ┌────────────────────────────────────────────────────────────┐ ║
║  │  VxRail Cluster (6 nodes)  |  vSAN datastore               │ ║
║  │                                                            │ ║
║  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐  │ ║
║  │  │  K8s Cluster │  │  PostgreSQL  │  │  Harbor        │  │ ║
║  │  │  (3 masters  │  │  Patroni HA  │  │  Registry      │  │ ║
║  │  │  + 6 workers)│  │  Primary +   │  │  vxrail-       │  │ ║
║  │  │              │  │  2 replicas  │  │  harbor.local  │  │ ║
║  │  └──────────────┘  └──────────────┘  └────────────────┘  │ ║
║  │                                                            │ ║
║  │  ┌──────────────────────────────────────────────────────┐ │ ║
║  │  │  Veeam B&R v12.1                                     │ │ ║
║  │  │  Daily VM snapshots → NAS Repository                 │ │ ║
║  │  │  PostgreSQL WAL → continuous archiving               │ │ ║
║  │  └──────────────────────────────────────────────────────┘ │ ║
║  └────────────────────────────────────────────────────────────┘ ║
║                           │                                      ║
║           ┌───────────────┼───────────────────┐                 ║
║           │               │                   │                 ║
║           ▼               ▼                   ▼                 ║
║  Replication          WAL archive         VM snapshots          ║
║  (pglogical /         to S3/NAS           to Veeam repo         ║
║   streaming)                                                     ║
╚═══════════════════════════╪══════════════════════════════════════╝
                            │  WAN / VPN (IPSec)
╔═══════════════════════════▼══════════════════════════════════════╗
║              DR SITE — Azure (Cold / Warm Standby)              ║
║                                                                  ║
║  ┌────────────────────────────────────────────────────────────┐ ║
║  │  Azure Blob Storage                                        │ ║
║  │  • Veeam backup copies (encrypted, 30-day retention)       │ ║
║  │  • PostgreSQL WAL archives (7-day PITR window)             │ ║
║  │  • K8s manifests + Helm charts (Git-synced)                │ ║
║  └────────────────────────────────────────────────────────────┘ ║
║                                                                  ║
║  ┌──────────────────────────────┐  ┌──────────────────────────┐ ║
║  │  Azure VMs (warm standby)    │  │  Azure AKS (cold standby)│ ║
║  │  Restore Veeam → Azure VM    │  │  Redeploy from manifests │ ║
║  │  RTO: 2-4 hours              │  │  RTO: 4-6 hours          │ ║
║  └──────────────────────────────┘  └──────────────────────────┘ ║
╚══════════════════════════════════════════════════════════════════╝
```

---

## Flowchart 2 — RTO / RPO Target Visualisation

```
  TIME AXIS (hours from incident):
  ────────────────────────────────────────────────────────────────▶
  0h        1h        2h        4h        6h       12h       24h

  POSTGRESQL DATABASE:
  RPO: ◀══════ 1 hour of data at risk (WAL archiving) ══════▶
  RTO: ◀═══════════════ 2 hours to restore ════════════════▶
       │               │
       Incident        DB back online

  K8s WORKLOADS:
  RPO: ◀═══════════════ 24 hours (daily snapshot) ════════════════▶
  RTO: ◀════════════════════════ 4 hours to rebuild ══════════════▶
       │                         │
       Incident                  Apps back online

  FILE STORAGE:
  RPO: ◀═══════════════════════ 24 hours ══════════════════════════▶
  RTO: ◀════════════════════════════════════════════ 24 hours ══════▶

  CONFIGURATION (Git):
  RPO: ◀ near-zero (Git push every change)
  RTO: ◀ 1 hour │
       Incident  Re-apply manifests

  PRIORITY TIERS:
  ╔═══════════════════════════════════════════════════════════╗
  ║  P1 (0–2h):  PostgreSQL + API Gateway + Auth Service     ║
  ║  P2 (0–4h):  All microservices + Redis + RabbitMQ        ║
  ║  P3 (0–24h): Dev environments + archive data + logs      ║
  ╚═══════════════════════════════════════════════════════════╝
```

---

## Flowchart 3 — Failover Decision: Which Recovery Path?

```
                          ⚠  FAILURE DETECTED
                                   │
           ┌───────────────────────┼────────────────────────┐
           ▼                       ▼                        ▼
   ◆ What failed?           ◆ Severity?              ◆ Duration?
           │                       │                        │
  ┌────────┴────────┐     CRITICAL / HIGH          > RTO threshold?
  │                 │               │                        │
  ▼                 ▼               ▼                    YES / NO
INFRA             DATA           SERVICE
(hardware/        (DB corrupt /  (K8s pods /
 network)          data loss)     app errors)

  │                 │               │
  ▼                 ▼               ▼
◆ Recoverable     ◆ WAL restore   ◆ Pod restart /
  locally?          possible?       node drain?
  │                 │               │
 YES  NO           YES  NO         YES  NO
  │    │            │    │          │    │
  ▼    ▼            ▼    ▼          ▼    ▼
Fix  Trigger     PITR  Restore   Restart Fail over
in   site        restore from   pod     to DR
place failover   archive   Veeam         site

  RECOVERY PATHS:
  ┌────────────────────────────────────────────────────────────┐
  │ PATH A — Local fix (RTO < 30 min):                        │
  │   Restart service, reschedule pod, fix config             │
  ├────────────────────────────────────────────────────────────┤
  │ PATH B — PITR restore (RTO 1-2 hrs):                      │
  │   pg_basebackup + WAL replay to point-in-time             │
  ├────────────────────────────────────────────────────────────┤
  │ PATH C — Veeam VM restore (RTO 2-4 hrs):                  │
  │   Restore VM from last good snapshot (local or Azure)     │
  ├────────────────────────────────────────────────────────────┤
  │ PATH D — Full DR failover (RTO 4-6 hrs):                  │
  │   Activate Azure standby VMs + AKS, restore DB,           │
  │   redirect DNS to Azure endpoints                         │
  └────────────────────────────────────────────────────────────┘
```

---

## Flowchart 4 — Backup Schedule Timeline

```
  DAILY SCHEDULE (24-hour view):
  ════════════════════════════════════════════════════════════════

  00:00 ┤ ① PostgreSQL pg_basebackup (full base backup — weekly Sun)
        │
  01:00 ┤ ② Veeam VM backup job starts
        │   • K8s master VMs (all 3)
        │   • DB VMs (patroni-1, patroni-2, patroni-3)
        │   • Harbor VM
        │   Retention: 7 daily + 4 weekly + 12 monthly
        │
  03:00 ┤ ③ Veeam backup completes (expected ~2 hrs)
        │   ◆ Success? → Verify checksum → OK
        │             → FAIL → Alert on-call + retry
        │
  04:00 ┤ ④ Veeam copy job: replicate backup to Azure Blob Storage
        │
  06:00 ┤ ⑤ PostgreSQL WAL archive check
        │   • WAL segments streaming continuously → NAS
        │   • Confirm last_archived_wal updated
        │
  12:00 ┤ ⑥ Midday: Veeam SureBackup (automated restore test)
        │   • Spin up recovered VM in isolated vLAN
        │   • Boot test + heartbeat check
        │   • Report: PASS / FAIL
        │
  18:00 ┤ ⑦ Incremental Veeam backup (application VMs only)
        │
  23:00 ┤ ⑧ Retention cleanup: purge expired restore points

  PITR WINDOW:
  ┌─────────────────────────────────────────────────────┐
  │  WAL archives retained: 7 days                     │
  │  Can restore to any second within last 7 days      │
  │  pg_basebackup weekly + continuous WAL = full PITR │
  └─────────────────────────────────────────────────────┘
```


## Table of Contents
1. [DR Objectives](#dr-objectives)
2. [Backup Strategy](#backup-strategy)
3. [Database PITR](#database-pitr)
4. [DR Architecture Options](#dr-architecture-options)
5. [Failover Procedures](#failover-procedures)
6. [DR Testing](#dr-testing)
7. [Compliance & Insurance](#compliance--insurance)

---

## DR Objectives

### RTO & RPO Targets

```
Recovery Time Objective (RTO):
├── Database: 2 hours (restore from backup)
├── Kubernetes Workloads: 4 hours (rebuild from manifests)
├── File Storage: 24 hours (restore from backup)
└── Configuration: 1 hour (Git-based recovery)

Recovery Point Objective (RPO):
├── Database (PostgreSQL WAL): 1 hour (pg_basebackup + WAL)
├── Kubernetes State: 24 hours (daily snapshots)
├── Application Data (backups): 24 hours (daily backups)
└── Configuration (Git): Near-zero (real-time Git commits)
```

### Tiered Recovery Priority

```
Priority 1 (Restore within 2 hours):
- PostgreSQL database (mission-critical)
- API Gateway service (revenue impacting)
- Authentication service (blocks all users)

Priority 2 (Restore within 4 hours):
- Other microservices
- Cache layer (Redis)
- Message queue (RabbitMQ)
- Monitoring stack

Priority 3 (Restore within 24 hours):
- Development environments
- Historical data
- Archived logs
- Cold storage
```

---

## Backup Strategy

### PostgreSQL Backup Procedures

```bash
# Continuous WAL Archiving (for PITR - Point-in-Time Recovery)

# Enable WAL archiving in postgresql.conf:
wal_level = replica
archive_mode = on
archive_timeout = 60
archive_command = '/usr/bin/test ! -f /mnt/wal_archive/%f && /bin/cp %p /mnt/wal_archive/%f'

# Backup Schedule:
- Full Backup: Daily (Sunday midnight) via pg_basebackup
- Incremental WAL: Hourly (WAL files archived continuously)
- Backup Retention: 30 days
- Backup Location: /backup/postgresql/
- Veeam Integration: Scheduled backup job

# Full Backup Command (for Veeam):
sudo su - postgres -c "pg_basebackup -D /backup/postgresql/full_backup -F t -z -P"

# Compressed size: ~50 GB (from 650 GB uncompressed)
# Time to complete: 1-2 hours

# Backup Verification (daily):
sudo su - postgres -c "pg_restore -l /backup/postgresql/full_backup.tar.gz | wc -l"
# Should show: Tables ✓, Indexes ✓, Constraints ✓
```

### Kubernetes State Backup

```bash
# Backup Kubernetes manifests & etcd state

# Method 1: etcd Backup (complete cluster state)
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/etcd.crt \
  --key=/etc/etcd/etcd.key \
  snapshot save /backup/etcd-backup-$(date +%Y%m%d).db

# Method 2: ConfigMap/Secret Export
kubectl get configmap -A -o yaml > /backup/configmaps.yaml
kubectl get secret -A -o yaml > /backup/secrets.yaml

# Method 3: Application Manifests (Git repository)
# All Helm charts and Kubernetes manifests stored in Git
# Can rebuild cluster from Git commits

# Backup Schedule: Daily snapshots, weekly archives
# Backup Location: /backup/kubernetes/, /backup/etcd/
# Off-site Copy: Weekly sync to Azure Blob Storage
```

### File Storage Backup

```bash
# vSAN Persistent Volumes

# Method 1: vSAN Snapshots
# Automated via vSAN Data Protection policies
# Snapshot schedule: Hourly (6-hour retention)
# Space overhead: ~10% additional vSAN capacity

# Method 2: Veeam Application-Aware Backups
# Backup job: Daily (Sunday midnight)
# Retention: 30 days
# Compression: 40-50% reduction
# Deduplication: Enabled (reduces further)

# Restore Procedure:
# - Granular file restore (single file) < 1 minute
# - Full volume restore < 30 minutes
# - VM backup restore < 1 hour
```

---

## Database PITR (Point-in-Time Recovery)

### Recovery Procedures

```bash
# Scenario: Database corrupted at 14:30, discovered at 15:00
# Objective: Recover to 14:25 (before corruption)

# Step 1: Stop Applications (immediately)
kubectl scale deployment/api-gateway --replicas=0 -n prod

# Step 2: Stop Primary PostgreSQL (preserve WAL)
sudo systemctl stop postgresql-14

# Step 3: List Available Backups
ls -lh /backup/postgresql/full_backup-2024-*.tar.gz
# Expected: Multiple full backups (one per day)

# Step 4: Restore Latest Full Backup (before corruption)
# Use Sunday's backup (most recent full backup before corruption)
cd /backup/postgresql
tar xzf full_backup-2024-08-17.tar.gz -C /var/lib/pgsql/14/data/

# Step 5: Create recovery.conf

cat <<EOF | sudo tee /var/lib/pgsql/14/data/recovery.conf
restore_command = 'cp /mnt/wal_archive/%f "%p"'
recovery_target_time = '2024-08-17 14:25:00'
recovery_target_timeline = 'latest'
EOF

# Step 6: Start PostgreSQL (enters recovery mode)
sudo systemctl start postgresql-14

# PostgreSQL will:
# 1. Restore full backup
# 2. Replay WAL files up to recovery_target_time
# 3. Stop at specified time
# 4. Become available for connections

# Step 7: Verify Recovered State
sudo su - postgres -c "psql -d prod_db -c 'SELECT MAX(updated_at) FROM users;'"
# Should show: 2024-08-17 14:24:59 (before corruption)

# Step 8: If Correct, Promote to Primary
sudo rm /var/lib/pgsql/14/data/recovery.conf
sudo systemctl restart postgresql-14

# Step 9: Resume Applications
kubectl scale deployment/api-gateway --replicas=12 -n prod
```

### PITR Success Criteria

```
✓ Transaction time verified (recovered to specific timestamp)
✓ No data loss beyond RPO (1 hour)
✓ Data integrity verified (no corruption)
✓ Replication working (standby resynchronizes)
✓ Applications reconnecting successfully
```

---

## DR Architecture Options

### Option 1: Local NAS Backup (Implemented)

```
Primary: On-Premises VxRail (10.30.0.110-112)
    ↓
Veeam Backup Server (10.40.0.10)
    ↓
Local NAS (10.40.0.20) - 500 GB allocated
    ↓
Weekly Archive to Azure Blob Storage

RTO: 2 hours (restore from NAS)
RPO: 1 hour (continuous WAL archiving)
Cost: Low ($500/month for NAS)
Complexity: Low
Vulnerability: Single datacenter (not protected against site disaster)
```

### Option 2: Azure Standby (Recommended)

```
Primary: On-Premises VxRail
    ↓
Backup: Local NAS
    ↓
Secondary: Azure VMs (standby, synced weekly)
    ↓
Periodic Failover Testing

RTO: 4 hours (boot Azure VMs, restore from backup)
RPO: 24 hours (daily backup sync to Azure)
Cost: Medium ($2,000/month for standby Azure resources)
Complexity: Medium
Vulnerability: Hybrid (protects against site disaster)
```

### Option 3: Stretched vSAN Cluster

```
Primary: On-Premises VxRail Nodes 1-6
    ↓
Stretched vSAN: Same 6 nodes, different physical locations
    ↓
Secondary: Remote location (10 km away)
    ↓
Automatic Failover (< 30 seconds)

RTO: 30 seconds (automatic failover)
RPO: < 1 minute (synchronous replication)
Cost: High ($100K+ infrastructure investment)
Complexity: High
Vulnerability: Near-zero (full replication across sites)

Note: Requires:
- Dual datacenters
- Fast network link (< 5ms latency)
- 6+ additional nodes at secondary site
- Complex networking & management
```

---

## Failover Procedures

### Manual Failover to Azure (if On-Prem Disabled)

```bash
# Prerequisites:
# - On-prem infrastructure completely unavailable
# - Latest backup successfully copied to Azure
# - Azure VMs ready to boot

# Step 1: Boot Azure VMs (5 min)
az vm start --resource-group company-dr --name aks-prod-001
az vm start --resource-group company-dr --name postgres-dr-01

# Step 2: Restore PostgreSQL from Latest Backup (30 min)
psql -h postgres-dr.database.windows.net -U pguser -d prod_db \
  < /backups/prod-latest.dump

# Step 3: Restore Kubernetes Manifests (10 min)
kubectl apply -f /backups/kubernetes/deployments/
kubectl apply -f /backups/kubernetes/configmaps/
kubectl apply -f /backups/kubernetes/secrets/

# Step 4: Update DNS to Azure (2 min)
# api.company.com → Azure public IP

# Step 5: Verify Applications Online (10 min)
kubectl get pods -n prod
kubectl logs -f pod/api-gateway-xyz -n prod

# Total RTO: 60 minutes
# Data Loss: Up to 24 hours (last backup restore)
```

---

## DR Testing

### Monthly DR Drill Procedure

```bash
# Schedule: Last Sunday of every month (2-3 hours)
# Participants: DBA, Infrastructure Lead, Operations

# Step 1: Announce DR Drill (fake incident)
# Post to Slack: "🚨 DR DRILL STARTING - This is a test, not real incident"

# Step 2: Simulate Primary Site Failure
# Administratively stop production database (controlled shutdown)
sudo systemctl stop postgresql-14 --no-block
# or stop Kubernetes cluster
kubectl delete nodes k8s-prod-worker-01

# Step 3: Begin Failover (use documented runbook)
# Follow: "Failover to Azure" procedures
# Record time for each step
# Note any issues encountered

# Step 4: Verify DR Site Operational
# - Applications responding to requests
# - Database accessible
# - No data loss (should be < 24 hours of RPO)

# Step 5: Successful Restore Verification
# - Row counts match (SELECT COUNT(*) all tables)
# - Data integrity checks pass
# - Performance acceptable

# Step 6: Failback to Primary
# Restart on-prem systems
# Resynchronize database replication
# Resume production operations

# Step 7: Post-Drill Analysis
# - How long did failover take? (RTO)
# - How much data was lost? (RPO)
# - What went wrong?
# - Update runbooks
# - Schedule next drill

# Expected: Failover time improving each quarter as team gets faster
```

### DR Drill Checklist

```
- [ ] Team assembled and ready
- [ ] Incident declared and communicated
- [ ] Primary site failure simulated
- [ ] DR runbook followed step-by-step
- [ ] Each step timed (log timestamps)
- [ ] Issues documented as they occur
- [ ] Failover completed successfully
- [ ] DR site verified operational
- [ ] Failback completed successfully
- [ ] Post-drill debrief held
- [ ] Runbook updated with lessons learned
- [ ] Next DR drill scheduled
```

---

## Compliance & Insurance

### Backup Retention Policy

```
PRODUCTION BACKUPS:
├── Hourly: 24 hours (for PITR)
├── Daily: 30 days (standard retention)
├── Weekly: 90 days (archive)
└── Monthly: 1 year (compliance hold)

DEVELOPMENT BACKUPS:
├── Daily: 7 days
└── Weekly: 30 days

COMPLIANCE REQUIREMENTS:
├── HIPAA: 6-year retention (if health data)
├── PCI-DSS: 1-year retention (credit card data)
├── GDPR: Follow data retention rules
└── SOX: 7-year retention (financial data)
```

### Backup Security

```
✓ Encryption: AES-256 (all backups encrypted)
✓ Access Control: Only DBA can restore
✓ Audit Logging: All restore attempts logged
✓ Off-Site Copy: Weekly encrypted copy to Azure
✓ Integrity Verification: Hash verification on restore
✓ Test Restore: Weekly restore test to verify integrity
```

### Insurance & Compliance Documentation

```
Required Documentation:
- [ ] Backup policy (frequency, retention, locations)
- [ ] DR plan (procedures, timelines, contacts)
- [ ] DR drill results (monthly test records)
- [ ] RTO/RPO SLA documentation
- [ ] Compliance mapping (HIPAA/PCI/GDPR)
- [ ] Risk assessment (what can fail, impact)
- [ ] Insurance policy (cyber liability coverage)
- [ ] Incident response plan (escalation, communication)
```

---

**Reference**: [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md), [09-Rollback-Procedures.md](./09-Rollback-Procedures.md), [12-Cutover-Runbook.md](./12-Cutover-Runbook.md)

