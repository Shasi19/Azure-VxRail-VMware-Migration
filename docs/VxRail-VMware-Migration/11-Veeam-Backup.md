# Veeam Backup and Replication — VxRail Migration Guide

> Your team uses **Veeam Backup and Replication (VBR)** for all VM protection. This guide covers Veeam setup on VxRail, backup strategy for Oracle Linux VMs, Kubernetes workloads, and databases (PostgreSQL and MongoDB).

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────┐
│                    VxRail HCI Cluster                       │
│                                                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │
│  │ K8s Master  │  │ K8s Workers │  │  DB VMs         │   │
│  │ 1/2/3       │  │ 1-6         │  │  PG + Mongo     │   │
│  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘   │
│         │                │                   │            │
│         └────────────────┴───────────────────┘            │
│                      VMware APIs                           │
│                          │                                 │
│         ┌────────────────┴──────────────┐                 │
│         │   Veeam Backup and Replication│                 │
│         │   Server (Windows 2022)       │                 │
│         │   vCenter Proxy: vxrail-vbr-01│                 │
│         └────────────────┬──────────────┘                 │
│                          │                                 │
└──────────────────────────┼─────────────────────────────────┘
                           │ Veeam Data Mover
           ┌───────────────┴────────────────┐
           │       Backup Repository         │
           │   (NAS / vSAN / Tape)           │
           │   /backup on NFS mount          │
           └────────────────────────────────┘
```

---

## 1. Veeam Backup and Replication Installation

### 1.1 Requirements

| Component | Specification |
|-----------|--------------|
| OS | Windows Server 2022 Datacenter |
| CPU | 8 vCPUs |
| RAM | 16 GB (32 GB for large environments) |
| System disk | 100 GB C: drive |
| Catalog disk | 500 GB D: drive (for VM backup catalog) |
| Veeam version | Veeam B&R v12.1 (latest) |
| SQL | Veeam installs SQL Server Express by default; use SQL Server Standard for prod |
| License | Veeam Universal License (VUL) — covers VMs + agents + K8s |
| VM placement | vxrail-vbr-01, hosted on one of the 6 VxRail nodes |

### 1.2 Veeam VBR VM Creation

```powershell
# Run these govc commands from jump host to create the Veeam server VM

# Create Veeam VM on VxRail node 5 (dedicated to services)
govc vm.create `
  -c=8 `
  -m=16384 `
  -disk=120GB `
  -net="PG-Management" `
  -g=windows2022srvNext_64Guest `
  -on=false `
  vxrail-vbr-01

# Add second disk for catalog/repositories
govc vm.disk.create `
  -vm=vxrail-vbr-01 `
  -size=500GB `
  -ds=vsanDatastore `
  -name="vbr-catalog"

# Power on and install Windows Server 2022 via vCenter console
govc vm.power -on vxrail-vbr-01
```

### 1.3 Install Veeam B&R v12

```powershell
# On Windows Server (vxrail-vbr-01) — run PowerShell as Administrator

# Download Veeam ISO (get link from veeam.com with your license)
# Mount the ISO or extract it, then run:

# Install Veeam B&R silently
.\setup.exe /silent /accepteula /acceptthirdpartylicenses `
  /installdir="C:\Program Files\Veeam\Backup and Replication\" `
  /noreboot

# After installer finishes, activate license
# Go to: Veeam B&R Console -> License -> Install License -> upload .lic file
```

### 1.4 Add vCenter to Veeam

1. Open **Veeam Backup and Replication Console**
2. Go to **Backup Infrastructure** → **Managed Servers** → **Add Server** → **VMware vSphere**
3. Enter vCenter FQDN: `vcenter.internal.company.com`
4. Credentials: `administrator@vsphere.local` with your vCenter password
5. Test Connection → Finish

---

## 2. Backup Proxies (VMware Backup Performance)

### 2.1 Add vSphere Backup Proxy

Veeam uses proxies to read VM data from vSAN. Add one proxy per 2-3 ESXi hosts.

```
Veeam Console -> Backup Infrastructure -> Backup Proxies
-> Add VMware Backup Proxy
  Server: vxrail-vbr-01 (same as VBR server for small setup)
  Transport mode: Virtual appliance (hotadd) -- fastest for vSAN
  Connected datastores: vsanDatastore
  Max concurrent tasks: 4
```

**Transport mode — hotadd** is recommended for vSAN:
- Veeam proxy is a VM on same vSAN cluster
- Reads backup data directly from vSAN without going through network
- 3-5x faster than network transport

### 2.2 Backup Repository Setup

```
Veeam Console -> Backup Infrastructure -> Backup Repositories
-> Add Backup Repository -> Network Attached Storage (NFS)

NFS path: 10.0.6.20:/backup/veeam   (your NAS IP)
Mount path: E:\

OR if using vSAN for backup (smaller environments):
-> Windows -> Choose vxrail-vbr-01 -> D:\ drive (500GB)
  Scale-up Capacity: D:\VeeamBackup
```

```powershell
# On vxrail-vbr-01: Mount NFS share for backup repo (if using NAS)
# First, install NFS client feature
Install-WindowsFeature NFS-Client

# Map the NFS share
New-PSDrive -Name "E" -PSProvider FileSystem `
  -Root "\\10.0.6.20\backup\veeam" -Persist

# Or mount via GUI: Map Network Drive -> \\10.0.6.20\backup\veeam
```

---

## 3. VM Backup Jobs — All VxRail VMs

### 3.1 Backup Job: K8s Control Plane Nodes

```
Veeam Console -> Home -> Jobs -> Backup -> Virtual machine

Job Name: K8s-ControlPlane-Daily
  Description: Daily backup of K8s master nodes

Virtual Machines to back up:
  + k8s-master-1
  + k8s-master-2
  + k8s-master-3

Storage:
  Backup repository: VeeamRepo-NAS
  Restore points to keep: 14  (2 weeks)
  Advanced -> Enable inline data deduplication: ON
  Advanced -> Compression level: Optimal

Schedule:
  Run: Daily at 02:00 AM
  Backup window: 02:00 - 06:00

Guest OS processing:
  Enable application-aware processing: ON
  Guest credentials: oracle/pass (for quiesced snapshots)

Finish -> Enable job immediately
```

### 3.2 Backup Job: K8s Worker Nodes

```
Job Name: K8s-Workers-Weekly
  Description: Weekly backup of K8s worker nodes (stateless)

Virtual Machines:
  + k8s-worker-1 through k8s-worker-6

Storage:
  Restore points: 4 (4 weeks)

Schedule:
  Run: Weekly on Sunday at 01:00 AM

Note: Workers are stateless — weekly is sufficient.
      Actual data is in PVCs backed by vSAN (separate backup).
```

### 3.3 Backup Job: Database VMs (Most Critical)

```
Job Name: Database-VMs-Daily
  Description: Daily backup of all PostgreSQL and MongoDB VMs

Virtual Machines:
  + db-dev-01 (PostgreSQL Dev)
  + db-qa-01 (PostgreSQL QA)
  + db-preprod-01 (PostgreSQL PreProd)
  + db-prod-01 (PostgreSQL Prod — primary)
  + db-prod-02 (PostgreSQL Prod — replica, if applicable)
  + mongo-dev-01
  + mongo-qa-01
  + mongo-preprod-01
  + mongo-prod-01
  + mongo-prod-02
  + mongo-prod-03

Storage:
  Restore points: 30  (1 month)
  Compression: Dedupe-friendly (best for databases)

Guest OS Processing:
  Application-aware processing: ON
  Pre-freeze script: /opt/veeam/pre-freeze.sh
  Post-thaw script: /opt/veeam/post-thaw.sh

Schedule:
  Run: Daily at 01:00 AM
  Retry failed VMs: 3 times (30 min intervals)
```

### 3.4 Pre/Post Freeze Scripts for PostgreSQL on OL9

```bash
#!/bin/bash
# /opt/veeam/pre-freeze.sh — run inside VM before snapshot (as root)
# Flushes PostgreSQL to disk for consistent backup

echo "Veeam pre-freeze: flushing PostgreSQL..." >> /var/log/veeam-backup.log

# PostgreSQL — create a checkpoint
sudo -u postgres /usr/pgsql-15/bin/psql -c "CHECKPOINT;" 2>&1 >> /var/log/veeam-backup.log

# MongoDB — freeze writes
mongosh --quiet --eval "db.fsyncLock()" 2>&1 >> /var/log/veeam-backup.log

echo "Pre-freeze complete at $(date)" >> /var/log/veeam-backup.log
exit 0
```

```bash
#!/bin/bash
# /opt/veeam/post-thaw.sh — run after snapshot (resume normal operations)

echo "Veeam post-thaw: resuming services..." >> /var/log/veeam-backup.log

# MongoDB — unfreeze
mongosh --quiet --eval "db.fsyncUnlock()" 2>&1 >> /var/log/veeam-backup.log

echo "Post-thaw complete at $(date)" >> /var/log/veeam-backup.log
exit 0
```

```bash
# Deploy scripts to all DB VMs
for VM_IP in 10.0.5.11 10.0.5.12 10.0.5.13 10.0.5.14 \
             10.0.5.21 10.0.5.22 10.0.5.23 10.0.5.24; do
  ssh oracle@${VM_IP} "sudo mkdir -p /opt/veeam"
  scp pre-freeze.sh post-thaw.sh oracle@${VM_IP}:/tmp/
  ssh oracle@${VM_IP} "sudo mv /tmp/pre-freeze.sh /tmp/post-thaw.sh /opt/veeam/ && sudo chmod +x /opt/veeam/*.sh"
done
```

---

## 4. Veeam Agent for Linux on Oracle Linux 9

VM-level agentless backup is the primary method. However, for granular file-level restores and when a VM cannot be powered off for snapshots, deploy Veeam Agent for Linux.

### 4.1 Install Veeam Agent on OL9

```bash
# On each Oracle Linux 9 VM — run as oracle with sudo

# Add Veeam Agent repo
sudo rpm --import https://www.veeam.com/downloads/keys/rpm-GPG-KEY-veeam-2024
sudo curl -Lo /etc/yum.repos.d/veeam.repo \
  https://repository.veeam.com/backup/linux/rhel/x86_64/veeam.repo

# Install
sudo dnf install -y veeam

# Check version
veeam --version

# Register with Veeam Backup Server
sudo veeamconfig vbrserver add \
  --name vxrail-vbr-01 \
  --address 10.0.1.40 \
  --port 10006 \
  --login veeam_agent_svc \
  --password 'VeeamAgent2026!'

# Verify connection
sudo veeamconfig vbrserver list
```

### 4.2 Configure Veeam Agent Job (K8s nodes)

```bash
# Create agent backup job on K8s master nodes
# (VM-level backup also covers masters — agent gives extra protection)

sudo veeamconfig job create filelevel \
  --name "K8s-Master-etcd-backup" \
  --objects "/etc/kubernetes,/var/lib/etcd" \
  --reponame "VeeamRepo-NAS" \
  --dailyAt "03:00" \
  --backupkind last \
  --keepLastRestorePoints 14

# List jobs
sudo veeamconfig job list

# Run job immediately (optional)
sudo veeamconfig job start --name "K8s-Master-etcd-backup"

# Check job status
sudo veeamconfig session list --jobname "K8s-Master-etcd-backup"
```

---

## 5. Kubernetes Workload Backup with Kasten K10

For Kubernetes-native backup (PVCs, ConfigMaps, Secrets, etcd), use **Kasten K10 by Veeam**, which integrates with Veeam VBR.

### 5.1 Install Kasten K10

```bash
# Add Kasten Helm repo
helm repo add kasten https://charts.kasten.io/
helm repo update

# Create namespace
kubectl create namespace kasten-io

# Install K10 (trial license includes 10 apps free)
helm install k10 kasten/k10 --namespace kasten-io \
  --set eula.accept=true \
  --set eula.company="YourCompany" \
  --set eula.email="admin@yourcompany.com" \
  --set auth.tokenAuth.enabled=true

# Watch pods come up
kubectl get pods -n kasten-io -w

# Expose K10 dashboard via LoadBalancer (uses MetalLB)
kubectl patch svc k10-gateway -n kasten-io \
  -p '{"spec":{"type":"LoadBalancer"}}'

# Get external IP
kubectl get svc k10-gateway -n kasten-io
# Access: http://<external-ip>/k10/#

# Get login token
kubectl -n kasten-io create token k10-k10 --duration=24h
```

### 5.2 Configure K10 Backup Storage

```bash
# Create a Veeam/S3-compatible location profile (pointing to MinIO)
# MinIO serves as S3-compatible object storage for K10

# Create location profile via K10 UI:
# Settings -> Location Profiles -> Add New
#   Infrastructure: S3-Compatible
#   Endpoint: http://10.0.6.12:9000 (MinIO internal)
#   Access key: kasten-backup
#   Secret key: <minio-secret>
#   Bucket: k10-backups
#   Prefix: cluster1

# OR via kubectl:
kubectl create secret generic k10-s3-secret \
  --namespace kasten-io \
  --from-literal=aws_access_key_id=kasten-backup \
  --from-literal=aws_secret_access_key='MinioBackup2026!'

kubectl apply -f - << 'EOF'
apiVersion: config.kio.kasten.io/v1alpha1
kind: Profile
metadata:
  name: minio-backup
  namespace: kasten-io
spec:
  type: Location
  locationSpec:
    credential:
      secretType: AwsAccessKey
      secret:
        apiVersion: v1
        kind: Secret
        name: k10-s3-secret
        namespace: kasten-io
    type: ObjectStore
    objectStore:
      name: k10-backups
      objectStoreType: S3
      endpoint: http://10.0.6.12:9000
      skipSSLVerify: true
      region: us-east-1
EOF
```

### 5.3 K10 Backup Policies (Per Environment)

```bash
# Backup all namespaces in Dev daily
kubectl apply -f - << 'EOF'
apiVersion: config.kio.kasten.io/v1alpha1
kind: Policy
metadata:
  name: dev-daily-backup
  namespace: kasten-io
spec:
  frequency: "@daily"
  retention:
    daily: 7
    weekly: 4
  selector:
    matchExpressions:
    - key: k8s.io/app
      operator: DoesNotExist
  actions:
  - action: backup
    backupParameters:
      profile:
        namespace: kasten-io
        name: minio-backup
EOF

# Similarly for qa-daily-backup, preprod-weekly-backup, prod-daily-backup
# (replace selector and retention values)
```

---

## 6. Backup Schedules Summary

| Job Name | Type | What | Schedule | Retention | Priority |
|----------|------|------|---------|-----------|----------|
| Database-VMs-Daily | VM Snapshot (Veeam) | All PostgreSQL + MongoDB VMs | Daily 01:00 | 30 days | Critical |
| K8s-ControlPlane-Daily | VM Snapshot (Veeam) | 3 Master nodes | Daily 02:00 | 14 days | High |
| K8s-Workers-Weekly | VM Snapshot (Veeam) | 6 Worker nodes | Weekly Sun 01:00 | 4 weeks | Medium |
| Services-VMs-Daily | VM Snapshot (Veeam) | Harbor, MinIO, Monitoring | Daily 03:00 | 7 days | Medium |
| etcd-Agent-Daily | Veeam Agent | /etc/kubernetes + /var/lib/etcd | Daily 03:00 | 14 days | High |
| K8s-Workloads-Dev | K10 | All Dev namespaces + PVCs | Daily | 7d/4w | Medium |
| K8s-Workloads-QA | K10 | All QA namespaces + PVCs | Daily | 7d/4w | Medium |
| K8s-Workloads-Prod | K10 | All Prod namespaces + PVCs | Daily | 30d/12w | Critical |

---

## 7. Restore Procedures

### 7.1 Full VM Restore

```
Veeam Console -> Home -> Backups -> Disk
-> Right-click VM -> Restore entire VM

  Restore to: Original location (overwrites existing VM)
  Restore to: New location (restore beside original — recommended)
    New name: db-prod-01-restored
    Datastore: vsanDatastore
    Network: PG-Databases

Power on restored VM -> verify -> cutover DNS
```

### 7.2 Instant VM Recovery (VM won't start — fastest RTO)

```
Veeam Console -> Home -> Backups -> Disk
-> Right-click VM -> Instant Recovery -> VMware vSphere

  This boots the VM directly FROM the backup repository
  RTO: 2-3 minutes

While running from backup, Veeam migrates data to vSAN in background.
Stop publishing when migration completes.
```

### 7.3 File-Level Recovery (Restore individual files)

```
Veeam Console -> Home -> Backups -> Disk
-> Right-click VM -> Guest Files Recovery -> Linux (ext3/ext4/XFS)

  Mount backup as read-only filesystem
  Browse files -> Download or Copy To -> restore location

Useful for: restore a deleted config file, recover a DB dump file, etc.
```

### 7.4 PostgreSQL Database Restore

```bash
# Option 1: Restore from Veeam VM backup
# Power on restored DB VM, then pg_dump the table you need

# Option 2: Use Veeam Explorer for PostgreSQL (if licensed)
# Veeam Console -> Home -> Backups -> Disk -> DB VM
# -> Application Items -> PostgreSQL -> select table/schema

# Option 3: Manual PITR from pg_basebackup
# (if pg_basebackup configured — see patching guide for PostgreSQL backups)

# Restore from nightly pg_dump file:
DB_NAME="prod_db"
DUMP_FILE="/backup/pg_dumps/prod_db_$(date +%Y%m%d).sql.gz"

# On the DB VM
sudo -u postgres /usr/pgsql-15/bin/dropdb --if-exists "${DB_NAME}_restore"
sudo -u postgres /usr/pgsql-15/bin/createdb "${DB_NAME}_restore"
zcat "$DUMP_FILE" | sudo -u postgres /usr/pgsql-15/bin/psql "${DB_NAME}_restore"

# Verify then rename if needed
sudo -u postgres /usr/pgsql-15/bin/psql -c "SELECT count(*) FROM information_schema.tables;"
```

---

## 8. Veeam ONE — Monitoring and Reporting

Veeam ONE provides a dashboard for backup health, SLA compliance, and resource usage.

### 8.1 Install Veeam ONE

```
Prerequisites: Windows Server 2022 (same server as VBR is fine for small env)

Download: https://www.veeam.com/products/veeam-one.html

Install Veeam ONE alongside VBR Server on vxrail-vbr-01:
  - Veeam ONE Monitor (connects to VBR and vCenter)
  - Veeam ONE Reporter (generates SLA reports)

Access: https://vxrail-vbr-01:1340/
```

### 8.2 Key Alerts to Configure

```
Veeam ONE -> Alarms -> Configure

Recommended alarms:
- Backup job failure: Alert immediately -> Email + Teams webhook
- Backup repository free space < 20%: Warning
- Backup repository free space < 10%: Critical
- VM not backed up in 24h (databases): Critical
- VM not backed up in 72h (workers): Warning
- Backup job duration > 4 hours: Warning (performance issue)
- VM RPO violation: Critical (if backup older than SLA allows)
```

### 8.3 SLA Reports

```
Veeam ONE Reporter -> Reports -> Protected VMs SLA

Configure weekly email report:
  Recipients: ops-team@yourcompany.com
  Schedule: Monday 09:00
  Include: Backup success rate, job failures, recovery point history
```

---

## 9. Veeam Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Snapshot consolidation failed | Too many delta files on vSAN | Manually consolidate: vCenter -> VM -> Snapshots -> Consolidate |
| Agent not connecting to VBR | Firewall blocking port 10006 | `firewall-cmd --add-port=10006/tcp --permanent --reload` on OL9 |
| Backup fails: quiesce error | VMware Tools not running | `systemctl status vmtoolsd`; reinstall `dnf install open-vm-tools` |
| Repository full | Disk space exhausted | `du -sh /backup/*`; clean old restore points; expand NFS share |
| VSS error on Linux VMs | Not applicable (Linux uses vSphere VMX snapshots) | Use pre/post-freeze scripts instead |
| etcd backup incomplete | etcd not quiesced | Use etcdctl snapshot save in the agent pre-freeze script |
| K10 backup fails | PV not accessible | `kubectl get pvc -A`; check StorageClass; check vSAN policy |
| K10 can't reach MinIO | Network policy blocking | Add NetworkPolicy allow rule for kasten-io namespace |

### Network Ports for Veeam on OL9

```bash
# Open on VBR server (Windows — via Windows Firewall)
# Veeam Agent -> VBR: 10006 (incoming on VBR server)
# VBR -> vCenter:  443
# VBR -> ESXi:     443, 902 (data)
# VBR -> Agent:    10002 (data path)

# Open on Oracle Linux VMs (for Veeam Agent outbound)
sudo firewall-cmd --permanent --add-port=10006/tcp  # VBR communication
sudo firewall-cmd --permanent --add-port=10002/tcp  # Data path
sudo firewall-cmd --reload
```
