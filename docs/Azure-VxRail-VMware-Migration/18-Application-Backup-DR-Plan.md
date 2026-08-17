# Application Backup and Disaster Recovery Plan

**Scope:** All environments (QA / PREPROD / PROD) | VxRail On-Premises**

> This document covers application-level backup and DR — complementing infrastructure-level
> backup in [11-Veeam-Backup.md](./11-Veeam-Backup.md) and the DR strategy in
> [10-Disaster-Recovery-Strategy.md](./10-Disaster-Recovery-Strategy.md).

---

## Backup Architecture Overview

```
FULL BACKUP STACK — WHAT GETS BACKED UP AND HOW
═══════════════════════════════════════════════════════════════════════════════

  ┌──────────────────────────────────────────────────────────────────────────┐
  │                        APPLICATION LAYER                                 │
  │   K8s Namespace Manifests   ConfigMaps   Secrets   PersistentVolumes     │
  │         │                       │            │              │            │
  │         ▼                       ▼            ▼              ▼            │
  │   ┌──────────────────────────────────────────────────────────────────┐   │
  │   │  Kasten K10 (Kubernetes-native backup)                           │   │
  │   │  - Backs up entire namespace: deployments, services, PVCs        │   │
  │   │  - Schedule: Daily at 02:00, retention 30 days                   │   │
  │   │  - Stores to vSAN + optional offsite S3-compatible               │   │
  │   └──────────────────────────────────────────────────────────────────┘   │
  └──────────────────────────────────────────────────────────────────────────┘

  ┌──────────────────────────────────────────────────────────────────────────┐
  │                          DATABASE LAYER                                   │
  │   PostgreSQL 15 (Patroni HA)                                              │
  │         │                                                                 │
  │         ├──▶ Streaming WAL replication → pg-*-02 + pg-*-03 (real-time)  │
  │         │                                                                 │
  │         ├──▶ WAL archiving → /data/wal-archive/ (PITR base)             │
  │         │    Retention: 7 days of WAL = any point-in-time restore        │
  │         │                                                                 │
  │         ├──▶ pg_basebackup (nightly) → /backup/pg-base-<date>/          │
  │         │    Retention: 14 daily + 4 weekly + 3 monthly                  │
  │         │                                                                 │
  │         └──▶ Veeam Agent for PostgreSQL VM → Veeam Repository            │
  │              Schedule: Daily 03:00, retention 30 days                    │
  └──────────────────────────────────────────────────────────────────────────┘

  ┌──────────────────────────────────────────────────────────────────────────┐
  │                        INFRASTRUCTURE LAYER                               │
  │   Veeam Backup and Replication v12                                        │
  │   - VM-level backup (all VMs: masters, workers, DB nodes)                 │
  │   - Schedule: Daily 01:00, retention 30 days                             │
  │   - Backup repository: on-prem NAS (primary) + optional cloud            │
  │   See 11-Veeam-Backup.md for full Veeam setup                            │
  └──────────────────────────────────────────────────────────────────────────┘

  ┌──────────────────────────────────────────────────────────────────────────┐
  │                     CONFIGURATION / GITOPS LAYER                          │
  │   All K8s manifests in Git (ArgoCD source of truth)                       │
  │   - Repo: github.com/your-org/k8s-manifests                              │
  │   - Branches: qa / preprod / main (prod)                                  │
  │   - Any accidental deletion is recovered by ArgoCD re-sync               │
  └──────────────────────────────────────────────────────────────────────────┘
```

---

## RTO and RPO Targets by Service

```
┌────────────────────────┬──────────┬──────────┬──────────────────────────────┐
│ Service / Component    │ RTO      │ RPO      │ Recovery Method              │
├────────────────────────┼──────────┼──────────┼──────────────────────────────┤
│ PROD API Gateway       │ < 5 min  │ 0        │ Kubernetes self-heals pods   │
│ PROD Application Pods  │ < 5 min  │ 0        │ K8s restarts failed pods     │
│ PROD PostgreSQL (HA)   │ < 30 s   │ 0        │ Patroni auto-failover        │
│ PROD PostgreSQL (DR)   │ < 4 hr   │ < 15 min │ PITR from WAL archives       │
│ Entire PROD namespace  │ < 2 hr   │ < 24 hr  │ Kasten K10 restore           │
│ PROD VM (single)       │ < 1 hr   │ < 24 hr  │ Veeam VM restore             │
│ Entire PROD cluster    │ < 8 hr   │ < 24 hr  │ Full Veeam restore + redeploy│
├────────────────────────┼──────────┼──────────┼──────────────────────────────┤
│ PREPROD PostgreSQL     │ < 30 s   │ 0        │ Patroni auto-failover        │
│ QA PostgreSQL          │ < 15 min │ < 24 hr  │ pg_restore from daily backup │
├────────────────────────┼──────────┼──────────┼──────────────────────────────┤
│ K8s control plane      │ < 30 min │ 0        │ etcd quorum (3 masters)      │
│ VxRail node failure    │ < 5 min  │ 0        │ vSphere HA VM restart        │
└────────────────────────┴──────────┴──────────┴──────────────────────────────┘
```

---

## Part 1: Kasten K10 — Kubernetes Namespace Backup

### Why Kasten K10?

```
WHY KASTEN K10 (not just Veeam):
════════════════════════════════════════════════════════════════

  Veeam backs up VMs → recovers the VM
  Kasten K10 backs up K8s namespace → recovers the application

  When you need K10:
  ┌──────────────────────────────────────────────────────────────┐
  │  "Someone ran: kubectl delete namespace prod"                │
  │  → Veeam cannot help (VM is fine, namespace is deleted)      │
  │  → K10 restores: deployments, services, PVCs, secrets in 1 step│
  └──────────────────────────────────────────────────────────────┘

  K10 captures:
  ├── Deployments, StatefulSets, DaemonSets
  ├── Services, Ingresses, ConfigMaps
  ├── Secrets (encrypted at rest)
  ├── PersistentVolumeClaims + data snapshots (vSAN CSI)
  └── RBAC, NetworkPolicies, ServiceAccounts
```

### Install Kasten K10

```bash
# Add Kasten Helm repo
helm repo add kasten https://charts.kasten.io/
helm repo update

# Create namespace
kubectl create namespace kasten-io

# Install K10 (with vSphere CSI snapshot support)
helm install k10 kasten/k10 \
  --namespace kasten-io \
  --set global.persistence.storageClass=vsan-prod \
  --set auth.basicAuth.enabled=true \
  --set auth.basicAuth.htpasswd='admin:$apr1$K10admin2026!' \
  --set metering.mode=airgap \   # No phone-home in air-gapped DC
  --set kanister.enabled=true    # App-consistent backups for databases

# Verify
kubectl get pods -n kasten-io
# All K10 pods should be Running within 5 minutes

# Access K10 dashboard
kubectl --namespace kasten-io port-forward service/gateway 8080:8080
# http://localhost:8080/k10/  (username: admin, password set above)
echo "K10 installed and accessible"
```

### Create Backup Policies

```bash
# Policy 1: PROD namespace — daily backup, 30-day retention
cat <<YAML | kubectl apply -f -
apiVersion: config.kio.kasten.io/v1alpha1
kind: Policy
metadata:
  name: prod-daily-backup
  namespace: kasten-io
spec:
  comment: "Daily PROD namespace backup — 30 day retention"
  frequency: "@daily"
  paused: false
  actions:
  - action: backup
    backupParameters:
      profile:
        namespace: kasten-io
        name: onprem-nas-profile        # Points to NAS backup repository
  - action: export
    exportParameters:
      frequency: "@weekly"             # Export weekly copy offsite
      profile:
        namespace: kasten-io
        name: s3-offsite-profile
      receiveString: ""
  retention:
    daily: 30
    weekly: 12
    monthly: 3
    yearly: 1
  selector:
    matchLabels:
      k10.kasten.io/appNamespace: prod
YAML

# Policy 2: PREPROD — daily, 14-day retention
cat <<YAML | kubectl apply -f -
apiVersion: config.kio.kasten.io/v1alpha1
kind: Policy
metadata:
  name: preprod-daily-backup
  namespace: kasten-io
spec:
  frequency: "@daily"
  actions:
  - action: backup
    backupParameters:
      profile:
        namespace: kasten-io
        name: onprem-nas-profile
  retention:
    daily: 14
    weekly: 4
  selector:
    matchLabels:
      k10.kasten.io/appNamespace: preprod
YAML

# Policy 3: QA — weekly, 4-week retention
cat <<YAML | kubectl apply -f -
apiVersion: config.kio.kasten.io/v1alpha1
kind: Policy
metadata:
  name: qa-weekly-backup
  namespace: kasten-io
spec:
  frequency: "@weekly"
  actions:
  - action: backup
    backupParameters:
      profile:
        namespace: kasten-io
        name: onprem-nas-profile
  retention:
    weekly: 4
  selector:
    matchLabels:
      k10.kasten.io/appNamespace: qa
YAML

echo "K10 backup policies created for all 3 environments"
```

### Restore a Namespace with K10

```bash
# Scenario: prod namespace accidentally deleted or corrupted

# List available restore points
kubectl get restorepoint -n kasten-io --selector=k10.kasten.io/appNamespace=prod

# Restore from most recent backup
cat <<YAML | kubectl apply -f -
apiVersion: actions.kio.kasten.io/v1alpha1
kind: RestoreAction
metadata:
  name: prod-restore-$(date +%Y%m%d)
  namespace: kasten-io
spec:
  subject:
    name: <restore-point-name>    # from kubectl get restorepoint output
    namespace: kasten-io
  targetNamespace: prod
  restoreClusterScopedResources: false
YAML

# Monitor restore progress
kubectl get restoreaction -n kasten-io -w
# Status moves: Running → Complete

# Verify after restore
kubectl get pods -n prod
kubectl get pvc -n prod
echo "Namespace restore complete"
```

---

## Part 2: PostgreSQL Backup and PITR

### PostgreSQL Backup Schedule

```
POSTGRESQL BACKUP LEVELS
════════════════════════════════════════════════════════════════

  Level 1: Streaming Replication (real-time, always-on)
  ────────────────────────────────────────────────────────
  Patroni → pg-*-02 + pg-*-03 (synchronous replica)
  RPO = 0 | RTO = < 30 seconds (automatic Patroni failover)
  Protects against: primary node failure, single disk failure

  Level 2: WAL Archiving (continuous, PITR-capable)
  ────────────────────────────────────────────────────────
  PostgreSQL archive_command → /data/wal-archive/
  Retention: 7 days
  RPO = point-in-time (any second in last 7 days)
  Protects against: accidental DELETE/DROP, data corruption

  Level 3: pg_basebackup (nightly snapshot)
  ────────────────────────────────────────────────────────
  Schedule: 02:00 daily via cron
  Retention: 14 daily + 4 weekly + 3 monthly
  Combined with WAL = full PITR capability
  Protects against: complete data loss, DR scenario

  Level 4: Veeam VM backup (daily, VM-level)
  ────────────────────────────────────────────────────────
  Schedule: 03:00 daily via Veeam
  Retention: 30 days
  See 11-Veeam-Backup.md for setup
  Protects against: VM corruption, OS failure
```

### Configure WAL Archiving

```bash
# Add to patroni.yml postgresql.parameters section
# (This enables PITR — point-in-time recovery)

# On pg-prod-01, edit /etc/patroni/patroni.yml
# Add under postgresql.parameters:
#   archive_mode: on
#   archive_command: 'cp %p /data/wal-archive/%f'
#   archive_timeout: 300      # Force archive every 5 min even if no WAL activity
#   restore_command: 'cp /data/wal-archive/%f %p'

# Apply by reloading Patroni config
patronictl -c /etc/patroni/patroni.yml reload prod-postgres

# Verify WAL archiving is working
psql -h 10.30.0.120 -U postgres -c "SELECT pg_switch_wal();"
ls /data/wal-archive/ | tail -5
# Should show .wal files appearing

# Monitor archive lag
psql -h 10.30.0.120 -U postgres -c "
SELECT pg_walfile_name(pg_current_wal_lsn()) AS current_wal,
       last_archived_wal,
       last_archived_time,
       archived_count,
       failed_count
FROM pg_stat_archiver;"
```

### pg_basebackup (Nightly)

```bash
# Create backup script
cat > /usr/local/bin/pg-basebackup.sh << 'SCRIPT'
#!/bin/bash
DATE=$(date +%Y%m%d)
BACKUP_DIR="/backup/pg-base-${DATE}"
LOG="/var/log/pg-backup-${DATE}.log"

echo "$(date) Starting pg_basebackup" >> "${LOG}"

pg_basebackup \
  -h 10.30.0.120 \
  -U postgres \
  -D "${BACKUP_DIR}" \
  --format=tar \
  --gzip \
  --compress=9 \
  --wal-method=stream \    # Include WAL needed to make backup consistent
  --checkpoint=fast \
  --progress \
  --verbose 2>> "${LOG}"

if [ $? -eq 0 ]; then
  echo "$(date) Backup SUCCEEDED: ${BACKUP_DIR}" >> "${LOG}"
  # Remove backups older than 14 days
  find /backup/ -name "pg-base-*" -mtime +14 -exec rm -rf {} + 2>/dev/null
else
  echo "$(date) Backup FAILED — check ${LOG}" >> "${LOG}"
  # Alert via monitoring system
fi
SCRIPT

chmod +x /usr/local/bin/pg-basebackup.sh

# Schedule daily at 02:00
echo "0 2 * * * postgres /usr/local/bin/pg-basebackup.sh" >> /etc/crontab
echo "pg_basebackup scheduled"
```

### Point-in-Time Recovery (PITR) Procedure

```
PITR DECISION FLOWCHART
════════════════════════════════════════════════════════════════

  Incident: Data loss or corruption detected
                    │
  ◆ When did corruption start?
  ├── Known time → PITR to T-1 minute before corruption
  └── Unknown → Check application logs to estimate time

  ◆ Which recovery level needed?
  ├── Last 30 seconds: Patroni failover (auto, no manual steps)
  ├── Last 7 days:     WAL-based PITR (steps below)
  └── Older than 7 days: pg_basebackup + WAL replay
```

```bash
# PITR Example: Recover to 2 hours ago (accidental mass DELETE at 14:00)
TARGET_TIME="2026-08-17 12:00:00"   # 2 hours before the DELETE

# Step 1: Stop Patroni on all nodes
for node in pg-prod-01 pg-prod-02 pg-prod-03; do
  ssh postgres@${node} "systemctl stop patroni"
done

# Step 2: Find the most recent pg_basebackup before target time
ls -lt /backup/pg-base-* | head -5
# Use the most recent one that was taken BEFORE the corruption

# Step 3: Restore base backup to a recovery directory
mkdir -p /data/pitr-recovery
tar xzf /backup/pg-base-20260817/base.tar.gz -C /data/pitr-recovery/

# Step 4: Create recovery.conf (PostgreSQL 15 uses postgresql.conf)
cat >> /data/pitr-recovery/postgresql.conf << EOF
restore_command = 'cp /data/wal-archive/%f %p'
recovery_target_time = '${TARGET_TIME}'
recovery_target_action = 'promote'    # Promote to read-write after reaching target
EOF
touch /data/pitr-recovery/recovery.signal  # Triggers PostgreSQL to enter recovery mode

# Step 5: Start PostgreSQL in recovery mode
chown -R postgres:postgres /data/pitr-recovery
su - postgres -c "PGDATA=/data/pitr-recovery /usr/pgsql-15/bin/pg_ctl start"

# Step 6: Watch recovery progress
tail -f /data/pitr-recovery/log/postgresql*.log | grep -E "recovery|redo|promote"
# Wait until: "database system is ready to accept connections"

# Step 7: Verify data is correct at the target time
psql -h 127.0.0.1 -p 5432 -U postgres -d prod_db -c \
  "SELECT count(*) FROM orders WHERE created_at < '${TARGET_TIME}';"

# Step 8: If correct, reconfigure as new primary and reinitialize Patroni
patronictl -c /etc/patroni/patroni.yml reinitialize prod-postgres pg-prod-02
patronictl -c /etc/patroni/patroni.yml reinitialize prod-postgres pg-prod-03
echo "PITR complete — cluster restored to ${TARGET_TIME}"
```

---

## Part 3: Disaster Recovery Runbook by Failure Scenario

```
DR SCENARIO DECISION TREE
════════════════════════════════════════════════════════════════

  FAILURE DETECTED
        │
  ◆ Which component failed?
  │
  ├──▶ Single pod crashed
  │        └── K8s auto-restarts → wait 60s → check kubectl describe pod
  │
  ├──▶ Database primary failed (node down)
  │        └── Patroni auto-failover → verify: patronictl list
  │            If auto-failover didn't trigger: see Scenario B below
  │
  ├──▶ Entire K8s worker node failed (VM down)
  │        └── vSphere HA restarts VM → pods reschedule → wait 5 min
  │            If VM won't start: see Scenario C below
  │
  ├──▶ K8s master node failed (1 of 3)
  │        └── etcd quorum maintained (2 of 3 still running) → cluster ok
  │            Replace the failed master: see Scenario D below
  │
  ├──▶ Entire K8s namespace deleted
  │        └── K10 restore → see Scenario E below
  │
  └──▶ VxRail host failure (entire physical server)
           └── vSphere HA restarts VMs on surviving hosts → see Scenario F
```

### Scenario A: Pod CrashLoopBackOff

```bash
# Diagnosis
kubectl describe pod <pod-name> -n prod | tail -30
kubectl logs <pod-name> -n prod --previous   # Logs from before the crash

# Common causes and fixes:

# 1. OOMKilled — increase memory limit
kubectl patch deployment api-gateway -n prod --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"2Gi"}]'

# 2. Liveness probe failing — check app startup time
kubectl patch deployment api-gateway -n prod --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":"60"}]'

# 3. Database connection refused — check PostgreSQL + pgBouncer
psql -h 10.30.0.200 -p 6432 -U app_user -d prod_db -c "SELECT 1;"
patronictl -c /etc/patroni/patroni.yml list

# 4. Secret missing — check secret exists
kubectl get secret postgres-prod-creds -n prod
```

### Scenario B: PostgreSQL Primary Failed, No Auto-Failover

```bash
# Check why Patroni didn't failover automatically
etcdctl --endpoints=http://10.30.0.120:2379,http://10.30.0.121:2379,http://10.30.0.122:2379 \
  endpoint health
# If etcd is unhealthy, Patroni cannot elect a new leader

# Manual failover
patronictl -c /etc/patroni/patroni.yml failover prod-postgres \
  --master pg-prod-01 \
  --candidate pg-prod-02 \
  --force

# Verify new leader
patronictl -c /etc/patroni/patroni.yml list
psql -h 10.30.0.200 -p 6432 -U postgres -d prod_db -c "SELECT pg_is_in_recovery();"
# Should return: f (false = primary/read-write)
```

### Scenario C: K8s Worker Node VM Won't Restart

```bash
# 1. Check vSphere — is the VM in a bad state?
govc vm.info "k8s-prod-worker-05"
govc vm.power -reset "k8s-prod-worker-05"   # Hard reset

# 2. If VM is corrupted, restore from Veeam backup
# (See 11-Veeam-Backup.md for restore procedure)
# After VM restores: kubelet auto-reconnects to cluster

# 3. If VM is unrecoverable, drain and replace
kubectl drain "k8s-prod-worker-05" \
  --ignore-daemonsets --delete-emptydir-data --force

# Create replacement VM (same specs)
govc vm.clone \
  -vm "/Datacenter/vm/Templates/ol9-k8s-template" \
  -name "k8s-prod-worker-05-new" \
  -m 98304 -c 24 -disk "300GB" \
  -pool "/Datacenter/host/VxRail-Cluster/Resources/PROD-Workers" \
  -net "VLAN-120-PROD"

# Configure OS (see 07-PROD-Detailed-Implementation.md Step 6)
# Join: kubeadm join 10.52.0.100:6443 ...
kubectl uncordon "k8s-prod-worker-05-new"
kubectl delete node "k8s-prod-worker-05"
echo "Worker replacement complete"
```

### Scenario D: K8s Master Node Failure (1 of 3)

```bash
# Cluster still functional (quorum = 2 of 3 masters)
# Verify remaining masters:
kubectl get nodes | grep master
kubectl get pods -n kube-system | grep etcd

# Replace the failed master
# 1. Remove from cluster
kubectl delete node "k8s-prod-master-02"

# 2. Create replacement VM (same IP if possible)
# 3. Configure OS (see 07-PROD-Detailed-Implementation.md Steps 2-4)
# 4. Join as control-plane
JOIN_CMD=$(kubeadm token create --print-join-command)
# Add --control-plane --certificate-key flag (from kubeadm init output)
kubeadm join 10.52.0.100:6443 \
  --token <new-token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <key>

kubectl get nodes | grep master
# All 3 masters should be Ready
```

### Scenario E: Entire Namespace Deleted (K10 Restore)

```bash
# Immediate action: don't panic — K10 has a backup

# List available restore points
kubectl get restorepoints -n kasten-io \
  -l k10.kasten.io/appNamespace=prod \
  --sort-by='.metadata.creationTimestamp' | tail -5

# Restore (takes 5-30 minutes depending on PVC size)
RESTORE_POINT=$(kubectl get restorepoints -n kasten-io \
  -l k10.kasten.io/appNamespace=prod \
  -o jsonpath='{.items[-1].metadata.name}')

cat <<YAML | kubectl apply -f -
apiVersion: actions.kio.kasten.io/v1alpha1
kind: RestoreAction
metadata:
  name: prod-emergency-restore
  namespace: kasten-io
spec:
  subject:
    name: ${RESTORE_POINT}
    namespace: kasten-io
  targetNamespace: prod
YAML

kubectl get restoreaction prod-emergency-restore -n kasten-io -w
# Wait for: status.state = Complete

kubectl get pods -n prod
echo "Namespace restored from K10 backup"
```

### Scenario F: VxRail Host Failure (Physical Server Down)

```bash
# vSphere HA automatically restarts VMs from failed host on surviving hosts
# Expected recovery time: 3-5 minutes (VM restart)

# 1. Check vSphere HA event log in vCenter UI
# 2. Verify VMs restarted on other hosts
govc vm.info k8s-prod-master-01 k8s-prod-worker-01
# Check "Host" field — should show a different physical host

# 3. Monitor K8s
kubectl get nodes -w
# Nodes should return to Ready state as VMs restart

# 4. Check for any data issues
patronictl -c /etc/patroni/patroni.yml list
# Patroni should show all 3 DB nodes — if one was on failed host,
# it auto-failovered before the host went down (< 30 s)

# 5. If host is permanently failed, rebalance VMs across 5 remaining hosts
govc cluster.rule.remove "prod-worker-anti-affinity"
# VMs redistributed via DRS within 10-15 minutes

echo "Host failure handled — cluster running on 5 of 6 hosts"
echo "Open support ticket with Dell for failed host replacement"
```

---

## Part 4: Secret Rotation and Key Management DR

```bash
# Why: Compromised secrets require rotation without downtime

# Step 1: Generate new credentials
NEW_DB_PASS=$(openssl rand -base64 32)
NEW_APP_KEY=$(openssl rand -hex 32)

# Step 2: Update secret in Kubernetes (rolling update — no downtime)
kubectl create secret generic postgres-prod-creds \
  --namespace prod \
  --from-literal=POSTGRES_PASSWORD="${NEW_DB_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Step 3: Update PostgreSQL user password
psql -h 10.30.0.200 -p 6432 -U postgres -d prod_db \
  -c "ALTER USER app_user PASSWORD '${NEW_DB_PASS}';"

# Step 4: Rolling restart of pods to pick up new secret
kubectl rollout restart deployment -n prod

# Step 5: Verify new credentials work
kubectl rollout status deployment -n prod --timeout=300s
curl -sf "http://$(kubectl get svc api-gateway -n prod \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/health" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])"
echo "Secret rotation complete"
```

---

## Part 5: Backup Verification Schedule

```
BACKUP VERIFICATION CALENDAR
══════════════════════════════════════════════════════════════════════

  Daily (automated):
  ├── Veeam job status check (email notification)
  ├── pg_basebackup completion log check
  ├── K10 policy run status
  └── WAL archive activity (pg_stat_archiver)

  Weekly:
  ├── Test pg_restore from latest backup (to test DB instance)
  ├── K10 restore drill: restore QA namespace to test-restore namespace
  ├── Review Patroni replication lag history
  └── Verify Veeam SureBackup (auto-verification) passed

  Monthly:
  ├── Full DR drill: simulate host failure, verify HA auto-recovery
  ├── PITR drill: restore PREPROD DB to T-2 hours
  ├── Kasten K10: full namespace restore drill (use staging cluster)
  ├── Review and update RTO/RPO actuals vs targets
  └── Update this document with any procedure changes

  Quarterly:
  ├── Full application DR simulation (tear down, restore from scratch)
  ├── Test Azure standby failover (keep Azure decommission delayed for 90 days)
  └── Review backup retention policies vs storage usage
```

---

## Part 6: Backup Storage Reference

```
BACKUP STORAGE LOCATIONS
══════════════════════════════════════════════════════════════════

  On-prem NAS (primary):
  ├── Mount: 10.20.0.30:/backup
  ├── Capacity: 50 TB (allocated from NAS appliance)
  ├── Path layout:
  │   ├── /backup/pg-base-*/          — pg_basebackup files
  │   ├── /backup/wal-archive/        — PostgreSQL WAL files
  │   ├── /backup/veeam/              — Veeam repository
  │   └── /backup/k10/                — Kasten K10 exports
  └── Retention managed per-backup-type (see above)

  Offsite (optional — configure when available):
  ├── S3-compatible object storage (MinIO or AWS S3)
  ├── Used by K10 for weekly exports and Veeam copy jobs
  └── Encryption: AES-256 server-side

  Backup space estimate:
  ├── pg_basebackup (PROD, compressed): ~100 GB/day × 14 = 1.4 TB
  ├── WAL archives (PROD): ~20 GB/day × 7 days = 140 GB
  ├── K10 (all namespaces, PVCs): ~500 GB
  ├── Veeam (all VMs, incremental): ~5 TB
  └── Total estimate: ~7-8 TB — well within 50 TB NAS allocation
```

---

**Related Documents:**
- [10-Disaster-Recovery-Strategy.md](./10-Disaster-Recovery-Strategy.md) — DR architecture
- [11-Veeam-Backup.md](./11-Veeam-Backup.md) — Veeam setup and restore procedures
- [09-Rollback-Procedures.md](./09-Rollback-Procedures.md) — Migration rollback procedures
- [12-Cutover-Runbook.md](./12-Cutover-Runbook.md) — Production cutover
- [14-Troubleshooting-Errors.md](./14-Troubleshooting-Errors.md) — Troubleshooting guide
- [00-VxRail-Complete-Index.md](./00-VxRail-Complete-Index.md) — Master index
