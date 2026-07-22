# Patching Strategy and Cycles — VxRail Migration Environment

> This guide defines patch cycles for all components: Oracle Linux 9 VMs, Kubernetes, PostgreSQL, MongoDB, VMware vSphere/VxRail, Veeam, and application workloads.

---

## Patch Cycle Overview

```
PATCH CYCLES

  Emergency Patches (P1)
  ├── Trigger: Critical CVE (CVSS > 9.0) or active exploit
  ├── Timeline: Within 24 hours
  └── Process: Emergency change request, immediate rollout

  Monthly Cycle (Security)
  ├── Scope: OS security patches (dnf security update)
  ├── Schedule: 3rd Tuesday of every month
  └── Environments: Dev → QA → PreProd → Prod (sequential)

  Quarterly Cycle (Full Patch)
  ├── Scope: OS + Kubernetes + Databases + Applications
  ├── Schedule: Q1=Jan, Q2=Apr, Q3=Jul, Q4=Oct
  └── Duration: Dev+QA (Week 1), PreProd (Week 2), Prod (Week 3)

  Semi-Annual Cycle (Infrastructure)
  ├── Scope: VMware vSphere + VxRail firmware + Veeam
  ├── Schedule: May and November
  └── Duration: Full weekend maintenance window

  Annual Cycle (Major Upgrades)
  ├── Scope: Kubernetes major version, PostgreSQL major version
  ├── Schedule: Q4 (October/November)
  └── Duration: 2-4 weeks per environment
```

---

## Patch Calendar (Full Year)

| Month | Cycle | Scope | Environments |
|-------|-------|-------|-------------|
| January | Quarterly Q1 | OS + K8s + DB + Apps | Dev→QA (Week 1), PreProd (Week 2), Prod (Week 3) |
| February | Monthly | OS Security | Dev→QA→PreProd→Prod (sequential) |
| March | Monthly | OS Security | Dev→QA→PreProd→Prod |
| April | Quarterly Q2 | OS + K8s + DB + Apps | Same pattern |
| May | Semi-Annual | VMware + VxRail + Veeam | All (rolling, one node at a time) |
| June | Monthly | OS Security | Dev→QA→PreProd→Prod |
| July | Quarterly Q3 | OS + K8s + DB + Apps | Same pattern |
| August | Monthly | OS Security | Dev→QA→PreProd→Prod |
| September | Monthly | OS Security | Dev→QA→PreProd→Prod |
| October | Quarterly Q4 + Annual | Full patch + major upgrades | Staged over 3 weeks |
| November | Semi-Annual | VMware + VxRail + Veeam | All (rolling) |
| December | Monthly | OS Security only | Dev→QA only (prod freeze) |

> **Production Freeze**: No patching in Prod from December 15 to January 15 (holiday freeze period).

---

## 1. Oracle Linux 9 Patching

### 1.1 Monthly Security Patch (All OL9 VMs)

```bash
#!/bin/bash
# ol9-monthly-security-patch.sh
# Run per environment — Dev first, then QA, then PreProd, then Prod

ENVIRONMENT=$1   # dev, qa, preprod, prod

# Map environment to hosts file
declare -A ENV_HOSTS
ENV_HOSTS[dev]="hosts-dev"
ENV_HOSTS[qa]="hosts-qa"
ENV_HOSTS[preprod]="hosts-preprod"
ENV_HOSTS[prod]="hosts-prod"

HOSTS_FILE="/etc/ansible/${ENV_HOSTS[$ENVIRONMENT]}"

echo "=== Monthly Security Patch: $ENVIRONMENT ==="
echo "Started: $(date)"

# Step 1: Pre-patch health check
echo "--- Pre-patch: Checking cluster health ---"
ansible all -i "$HOSTS_FILE" -m shell \
  -a "uptime && df -h / && free -m" --become

# Step 2: Check what will be updated (dry run)
echo "--- Security updates available ---"
ansible all -i "$HOSTS_FILE" -m shell \
  -a "dnf check-update --security 2>/dev/null | tail -20" --become

# Step 3: Apply security updates only (not all updates)
echo "--- Applying security updates ---"
ansible all -i "$HOSTS_FILE" -m shell \
  -a "dnf update -y --security" --become \
  --serial 1   # One host at a time (rolling)

# Step 4: Check if reboot required
echo "--- Checking for reboot requirement ---"
ansible all -i "$HOSTS_FILE" -m shell \
  -a "needs-restarting -r; echo ExitCode: \$?" --become

# Step 5: Rolling reboot (Ansible serial=1)
echo "--- Rolling reboot ---"
ansible all -i "$HOSTS_FILE" -m reboot \
  -a "reboot_timeout=300 post_reboot_delay=60" \
  --become --serial 1

# Step 6: Post-patch verification
echo "--- Post-patch verification ---"
ansible all -i "$HOSTS_FILE" -m shell \
  -a "uname -r && uptime" --become

echo "=== Patch complete: $ENVIRONMENT at $(date) ==="
```

### 1.2 Ansible Host Files

```ini
# /etc/ansible/hosts-dev
[k8s_masters]
10.0.3.11 ansible_user=oracle

[k8s_workers_dev]
10.0.4.21 ansible_user=oracle
10.0.4.22 ansible_user=oracle

[databases_dev]
10.0.5.11 ansible_user=oracle
10.0.5.21 ansible_user=oracle
```

```ini
# /etc/ansible/hosts-prod (K8s workers in pairs for rolling reboot)
[k8s_masters]
10.0.3.11 ansible_user=oracle
10.0.3.12 ansible_user=oracle
10.0.3.13 ansible_user=oracle

[k8s_workers_prod]
10.0.4.25 ansible_user=oracle
10.0.4.26 ansible_user=oracle

[databases_prod]
10.0.5.13 ansible_user=oracle
10.0.5.14 ansible_user=oracle
10.0.5.23 ansible_user=oracle
10.0.5.24 ansible_user=oracle
10.0.5.25 ansible_user=oracle
```

### 1.3 K8s Node Patch (Drain Before Reboot)

For K8s worker nodes, drain before rebooting to avoid pod disruption:

```bash
#!/bin/bash
# k8s-node-patch.sh — patch a K8s worker node gracefully
# Run from the jump host

NODE_NAME=$1        # e.g., k8s-worker-1
NODE_IP=$2          # e.g., 10.0.4.21

echo "=== Patching K8s node: $NODE_NAME ==="

# 1. Cordon: mark node unschedulable
kubectl cordon "$NODE_NAME"

# 2. Drain: evict all pods (except DaemonSets)
kubectl drain "$NODE_NAME" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60 \
  --timeout=300s

echo "Node drained. Waiting 10 seconds..."
sleep 10

# 3. SSH into node and apply patches
ssh oracle@"$NODE_IP" << 'REMOTE'
sudo dnf update -y --security
echo "Rebooting..."
sudo reboot
REMOTE

# 4. Wait for node to come back
echo "Waiting for node to reboot..."
sleep 60

# 5. Poll until node is Ready
for i in {1..30}; do
  STATUS=$(kubectl get node "$NODE_NAME" \
    -o jsonpath='{.status.conditions[-1].type}')
  if [ "$STATUS" = "Ready" ]; then
    echo "Node back: $NODE_NAME is Ready"
    break
  fi
  echo "  Attempt $i: Node status = $STATUS, waiting..."
  sleep 20
done

# 6. Uncordon: allow pods back
kubectl uncordon "$NODE_NAME"
echo "Node $NODE_NAME uncordoned"

# 7. Verify pods rescheduled
kubectl get pods -A --field-selector spec.nodeName="$NODE_NAME" | head -20
```

---

## 2. Kubernetes Patching (Quarterly)

### 2.1 K8s Version Strategy

| Version | Type | Action |
|---------|------|--------|
| 1.29.x (current) | Minor/patch | `dnf update kubelet kubeadm kubectl` |
| 1.29 → 1.30 | Minor version | kubeadm upgrade plan + upgrade apply |
| 1.30 → 1.31 | Minor version | Same — one minor at a time only |

> **K8s rule**: Never skip minor versions. 1.29 → 1.31 is NOT supported. Must do 1.29 → 1.30 → 1.31.

### 2.2 Kubernetes Patch Upgrade (1.29.0 → 1.29.4)

```bash
# === RUN ON: k8s-master-1 ===

# Unlock package version lock
sudo dnf versionlock delete kubelet kubeadm kubectl

# Check available patch versions
dnf list --showduplicates kubeadm | grep "1.29"

# Upgrade kubeadm first
sudo dnf install -y kubeadm-1.29.4 --disableexcludes=kubernetes

# Check upgrade plan (shows what will be upgraded)
sudo kubeadm upgrade plan

# Apply the upgrade (control plane only)
sudo kubeadm upgrade apply v1.29.4 --yes

# Upgrade kubelet and kubectl on master-1
sudo dnf install -y kubelet-1.29.4 kubectl-1.29.4 --disableexcludes=kubernetes
sudo systemctl daemon-reload && sudo systemctl restart kubelet

# Lock versions
sudo dnf versionlock add kubelet kubeadm kubectl
```

```bash
# === RUN ON: k8s-master-2 and k8s-master-3 (one at a time) ===

sudo dnf versionlock delete kubelet kubeadm kubectl
sudo dnf install -y kubeadm-1.29.4 --disableexcludes=kubernetes

# Upgrade this control plane node
sudo kubeadm upgrade node

sudo dnf install -y kubelet-1.29.4 kubectl-1.29.4 --disableexcludes=kubernetes
sudo systemctl daemon-reload && sudo systemctl restart kubelet
sudo dnf versionlock add kubelet kubeadm kubectl
```

```bash
# === RUN ON: jump host — upgrade all workers ===

WORKERS=(k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4 k8s-worker-5 k8s-worker-6)
WORKER_IPS=(10.0.4.21 10.0.4.22 10.0.4.23 10.0.4.24 10.0.4.25 10.0.4.26)

for i in "${!WORKERS[@]}"; do
  NODE="${WORKERS[$i]}"
  IP="${WORKER_IPS[$i]}"
  echo "=== Upgrading worker: $NODE ==="
  
  kubectl cordon "$NODE"
  kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data \
    --grace-period=60 --timeout=300s
  
  ssh oracle@"$IP" << REMOTE
sudo dnf versionlock delete kubelet kubeadm kubectl
sudo dnf install -y kubeadm-1.29.4 --disableexcludes=kubernetes
sudo kubeadm upgrade node
sudo dnf install -y kubelet-1.29.4 kubectl-1.29.4 --disableexcludes=kubernetes
sudo systemctl daemon-reload && sudo systemctl restart kubelet
sudo dnf versionlock add kubelet kubeadm kubectl
sudo reboot
REMOTE
  
  # Wait for node ready
  sleep 90
  kubectl wait --for=condition=Ready node/"$NODE" --timeout=5m
  kubectl uncordon "$NODE"
  echo "  Done: $NODE"
  sleep 30   # let pods reschedule before next worker
done

# Final verify
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running | grep -v Completed
```

---

## 3. PostgreSQL Patching

### 3.1 Minor Version Patch (e.g., 15.5 → 15.6)

```bash
# On each PostgreSQL VM (no pg_upgrade needed for minor versions)
# Minor versions are in-place: stop pg, update binary, start pg

sudo systemctl stop postgresql-15

# Update just PostgreSQL packages
sudo dnf update -y postgresql15 postgresql15-server postgresql15-contrib

# Restart
sudo systemctl start postgresql-15

# Verify new version
sudo -u postgres /usr/pgsql-15/bin/psql -c "SELECT version();"
```

### 3.2 Major Version Upgrade (e.g., 15 → 16)

```bash
# Major upgrade requires pg_upgrade
# Plan a maintenance window for this — Prod downtime needed

# On DB VM (db-prod-01)

# 1. Install new version alongside existing
sudo dnf install -y postgresql16 postgresql16-server postgresql16-contrib

# 2. Initialize new cluster
sudo /usr/pgsql-16/bin/postgresql-16-setup initdb

# 3. Stop current PostgreSQL
sudo systemctl stop postgresql-15

# 4. Run pg_upgrade (check mode first)
sudo -u postgres /usr/pgsql-16/bin/pg_upgrade \
  -b /usr/pgsql-15/bin \
  -B /usr/pgsql-16/bin \
  -d /var/lib/pgsql/15/data \
  -D /var/lib/pgsql/16/data \
  --check    # <-- dry run first

# 5. If check passes, run actual upgrade
sudo -u postgres /usr/pgsql-16/bin/pg_upgrade \
  -b /usr/pgsql-15/bin \
  -B /usr/pgsql-16/bin \
  -d /var/lib/pgsql/15/data \
  -D /var/lib/pgsql/16/data \
  --link    # hardlink instead of copy for speed

# 6. Update pg_hba.conf and postgresql.conf in new data dir
sudo cp /var/lib/pgsql/15/data/pg_hba.conf \
        /var/lib/pgsql/16/data/pg_hba.conf

# 7. Start new version
sudo systemctl enable postgresql-16
sudo systemctl start postgresql-16
sudo -u postgres /usr/pgsql-16/bin/psql -c "SELECT version();"

# 8. After verification, remove old version
sudo /usr/pgsql-16/bin/vacuumdb --all --analyze-in-stages
sudo dnf remove -y postgresql15 postgresql15-server
```

### 3.3 PostgreSQL Nightly Dump (Supplement to Veeam)

```bash
#!/bin/bash
# /opt/scripts/pg-nightly-dump.sh — run as oracle via cron

BACKUP_DIR="/backup/pg_dumps"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

# Dump each database
for DB in dev_db qa_db preprod_db prod_db; do
  sudo -u postgres /usr/pgsql-15/bin/pg_dump \
    --compress=9 \
    --format=custom \
    --file="${BACKUP_DIR}/${DB}_${DATE}.dump" \
    "$DB"
  echo "Dumped: $DB"
done

# Cleanup old dumps
find "$BACKUP_DIR" -name "*.dump" -mtime +${RETENTION_DAYS} -delete
echo "Cleanup done. Kept ${RETENTION_DAYS} days of dumps."
```

```bash
# Crontab entry (sudo crontab -e for oracle user)
# Run at 00:30 daily (before Veeam backup at 01:00)
30 0 * * * /opt/scripts/pg-nightly-dump.sh >> /var/log/pg-backup.log 2>&1
```

---

## 4. MongoDB Patching

### 4.1 Minor Version Patch

```bash
# Dev and QA (standalone MongoDB)
sudo systemctl stop mongod
sudo dnf update -y mongodb-org
sudo systemctl start mongod
mongosh --eval "db.adminCommand({serverStatus:1}).version"
```

```bash
# Prod (ReplicaSet rs-prod — rolling patch, one node at a time)
# Always patch SECONDARIES first, then step down PRIMARY last

# Step 1: Check replica set state
mongosh --quiet --eval "rs.status().members.forEach(m => print(m.name, m.stateStr))"

# Step 2: Patch secondary (e.g., mongo-prod-02)
ssh oracle@10.0.5.24 << 'REMOTE'
sudo systemctl stop mongod
sudo dnf update -y mongodb-org
sudo systemctl start mongod
REMOTE
sleep 30

# Step 3: Verify secondary caught up
mongosh --host 10.0.5.24 --quiet --eval "rs.status().myState"
# Should show 2 (SECONDARY)

# Step 4: Patch other secondaries, one at a time

# Step 5: Step down Primary and patch it
mongosh --quiet --eval "rs.stepDown()"
# Cluster elects new primary
ssh oracle@10.0.5.23 << 'REMOTE'
sudo systemctl stop mongod
sudo dnf update -y mongodb-org
sudo systemctl start mongod
REMOTE

# Step 6: Verify replica set healthy
mongosh --quiet --eval "rs.status()" | grep -E "stateStr|name"
```

---

## 5. VMware vSphere and VxRail Patching (Semi-Annual)

> **IMPORTANT**: Always use **VxRail Manager** to patch ESXi hosts — NEVER patch ESXi directly using VMware Update Manager (VUM) or esxcli. VxRail Manager ensures firmware + ESXi are patched together for Dell HW compatibility.

### 5.1 Pre-Patch Checklist

```bash
# Run from jump host before any VxRail patching

# 1. Check cluster health in vCenter
govc object.collect -type ClusterComputeResource \
  /Datacenter/host/VxRail-Cluster/ overallStatus

# 2. Check vSAN health
govc host.esxcli -host 10.0.0.11 vsan cluster get 2>/dev/null || true
# Use vSAN Health Check in vCenter UI: vSAN -> VxRail-Cluster -> Monitor -> Health

# 3. Verify DRS is enabled (needed for rolling patch)
# vCenter -> Cluster -> Configure -> vSphere DRS -> ON

# 4. Verify all VMs are on latest VMware Tools
govc find / -type m | while read vm; do
  govc vm.info "$vm" | grep "ToolsVersion"
done

# 5. Take Veeam backup of ALL VMs before patching
# Veeam Console -> Jobs -> Run all jobs now
```

### 5.2 VxRail Rolling ESXi Patch

```bash
# Process per VxRail node (one at a time, cluster-wide)
# DRS automatically migrates VMs to other nodes during patch

# Step 1: Download VxRail patch bundle from Dell Support
# Go to: https://www.dell.com/support -> VxRail -> Drivers & Downloads
# Download: VxRail-SDDC-SoftwareUpdate-<version>.zip

# Step 2: Upload to VxRail Manager
# VxRail Manager UI -> System -> LCM (Lifecycle Management)
# -> Upgrade Bundle -> Upload

# Step 3: Run pre-checks
# VxRail Manager -> System -> LCM -> Upgrade -> Run Pre-checks
# Fix any issues before proceeding

# Step 4: Start rolling upgrade
# VxRail Manager -> System -> LCM -> Upgrade -> Start Upgrade
# VxRail Manager patches one node at a time:
#   - Puts node in maintenance mode (DRS migrates VMs)
#   - Patches ESXi + Dell firmware
#   - Reboots node
#   - Exits maintenance mode
#   - Waits 5 min -> moves to next node

# Monitor progress in VxRail Manager (takes 2-4 hours for 6 nodes)
# Each node patch: ~25-35 minutes

# Step 5: Post-patch verification
govc about -host vcenter.internal.company.com | grep -i version
govc host.info  # check all 6 hosts show new ESXi version
```

### 5.3 vCenter Server Appliance (VCSA) Update

```bash
# VCSA updates are done AFTER all ESXi patches complete

# Access VCSA Management Interface
# https://vcenter.internal.company.com:5480

# Go to: Update -> Stage and Install -> Browse/Upload update
# OR use internet connection to check for updates directly

# Backup VCSA before update
# File-Based Backup: 5480 -> Backup -> Start
# Backup to NFS: nfs://10.0.6.20/vcsa-backup/

# After backup, apply update through 5480 UI
# Update takes 30-60 minutes, VCSA will restart
```

---

## 6. Veeam Patching

### 6.1 Veeam B&R Update

```powershell
# On vxrail-vbr-01 (Windows Server)
# Check for updates: Veeam Console -> Help -> Check for Updates

# Download the installer from Veeam website or via update mechanism
# Close Veeam Console before updating

# Run update (auto-stops and restarts all Veeam services)
# .\VeeamBackup_12.x.x.x.exe /silent /accepteula

# After update, verify:
Get-Service VeeamBackupSvc | Select-Object Name, Status, DisplayName
```

### 6.2 Veeam Agent for Linux Update (OL9)

```bash
# On each Oracle Linux 9 VM
sudo dnf update -y veeam

# Verify
veeam --version

# Restart agent service
sudo veeamservice restart
```

---

## 7. Application Patching (Helm Charts)

### 7.1 Harbor Registry Update

```bash
# Check current version
helm list -n harbor

# Update Helm repo
helm repo update

# Check available versions
helm search repo harbor/harbor --versions | head -10

# Upgrade Harbor (non-breaking — same major version)
helm upgrade harbor harbor/harbor \
  -n harbor \
  --reuse-values \
  --version 1.15.0   # specify new version

# Watch rollout
kubectl rollout status deployment/harbor-core -n harbor
kubectl get pods -n harbor
```

### 7.2 ArgoCD Update

```bash
# Check current version
kubectl get deploy argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'

# Apply new version (argocd uses GitHub releases)
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.0/manifests/install.yaml

# Monitor
kubectl rollout status deployment/argocd-server -n argocd
argocd version
```

### 7.3 Prometheus and Grafana (kube-prometheus-stack)

```bash
# Check current
helm list -n monitoring

# Update repo
helm repo update

# Check new versions
helm search repo prometheus-community/kube-prometheus-stack --versions | head -5

# Upgrade
helm upgrade kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --reuse-values \
  --version 65.0.0

# Verify
kubectl get pods -n monitoring
```

---

## 8. Patch Rollback Procedures

### 8.1 OS Rollback (OL9 — using GRUB boot menu)

```bash
# If a kernel update causes boot issues, boot from previous kernel

# On the affected node (via vCenter console if SSH not available)
# At GRUB menu: press 'e' to edit boot entry
# Change kernel version to previous

# After booting into previous kernel, lock bad kernel:
sudo dnf versionlock add kernel-$(uname -r)

# Verify
uname -r
rpm -q kernel --qf "%{VERSION}-%{RELEASE}.%{ARCH}\n" | sort
```

### 8.2 K8s Rollback

```bash
# If kubeadm upgrade causes issues

# Downgrade kubelet and kubectl
sudo dnf versionlock delete kubelet kubectl
sudo dnf install -y kubelet-1.29.0 kubectl-1.29.0 --disableexcludes=kubernetes
sudo dnf versionlock add kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet

# kubeadm control plane rollback (only if < 1 hour since upgrade)
# Note: kubeadm upgrade does not support rollback after etcd is migrated
# Best option: restore from Veeam VM backup (instant VM recovery)

# Restore from Veeam (fastest):
# Veeam Console -> Instant Recovery -> choose backup from before patch
```

### 8.3 PostgreSQL Rollback (Minor)

```bash
# If new minor version has bugs
sudo systemctl stop postgresql-15
sudo dnf downgrade postgresql15 postgresql15-server
sudo systemctl start postgresql-15
sudo -u postgres /usr/pgsql-15/bin/psql -c "SELECT version();"
```

### 8.4 Rollback Decision Tree

```
Patch applied -> Issue detected?
  YES ->
    Impact to Prod services?
      YES (critical) ->
        Invoke Veeam Instant Recovery immediately
        Raise P1 incident
        Notify management
        Target RTO: < 30 minutes
      NO (non-critical) ->
        Can downgrade package? -> dnf downgrade
        Cannot downgrade? -> restore from Veeam backup
        RTO: < 2 hours
  NO -> Monitor for 24 hours, then close patch window
```

---

## 9. Patch Approval and Change Management

### 9.1 Change Request Template

```
CHANGE REQUEST — Patch Cycle Q[n] [Year]

Requested By: [Name]
Change Type: Monthly Security / Quarterly Full / Emergency
Environments: Dev, QA, PreProd, Prod
Schedule: [Date/Time] to [Date/Time]
Duration: [Estimated hours]
Risk Level: Low / Medium / High

Components:
  - OS: Oracle Linux 9 — dnf update --security
  - K8s: [No change / 1.29.x → 1.29.y]
  - PostgreSQL: [No change / 15.x → 15.y]
  - VMware: [No change / ESXi 8.x → 8.y]

Pre-checks:
  [ ] Veeam backups successful for all VMs
  [ ] Cluster health: green
  [ ] vSAN health: green
  [ ] All services responding (run health-check.sh)

Rollback Plan:
  - Veeam Instant VM Recovery (RTO: 15 min)
  - dnf downgrade for package rollback

Approvals:
  - Dev/QA: Team Lead approval
  - PreProd: Manager approval
  - Prod: Manager + CTO approval (email required)
```

### 9.2 Post-Patch Verification Script

```bash
#!/bin/bash
# post-patch-verify.sh — run after every patch cycle

echo "=== Post-Patch Verification: $(date) ==="

# Kubernetes
echo "--- K8s Node Status ---"
kubectl get nodes -o wide

echo "--- K8s Pods (not Running/Completed) ---"
kubectl get pods -A | grep -vE "Running|Completed|Terminating"

echo "--- K8s Component Health ---"
kubectl get componentstatuses 2>/dev/null || true

# Applications
echo "--- Harbor ---"
curl -s -o /dev/null -w "%{http_code}" https://harbor.internal.company.com/api/v2.0/health
echo ""

echo "--- ArgoCD ---"
argocd app list 2>/dev/null | head -10 || echo "ArgoCD CLI not configured here"

# Databases
echo "--- PostgreSQL ---"
for IP in 10.0.5.11 10.0.5.12 10.0.5.13 10.0.5.14; do
  STATUS=$(PGPASSWORD=check sudo -u postgres /usr/pgsql-15/bin/pg_isready -h "$IP" 2>&1)
  echo "  $IP: $STATUS"
done

echo "--- MongoDB ---"
for IP in 10.0.5.21 10.0.5.22 10.0.5.23 10.0.5.24 10.0.5.25; do
  RESULT=$(mongosh --host "$IP" --quiet --eval "db.runCommand({ping:1}).ok" 2>/dev/null)
  echo "  $IP: ping=$RESULT"
done

echo "=== Verification complete ==="
```

---

## Complete Patching Procedures

### Oracle Linux 9 — Monthly Patch Procedure

```bash
#!/bin/bash
# ol9-patch.sh — Monthly patch script for Oracle Linux 9 VMs
# Run on each VM individually, or via Ansible (recommended)

set -euo pipefail
HOSTNAME=$(hostname)
LOG="/var/log/patching/$(date +%Y%m%d)-${HOSTNAME}.log"
mkdir -p /var/log/patching

echo "$(date): === OL9 Patch Start on $HOSTNAME ===" | tee -a $LOG

# 1. Check for available updates
echo "$(date): Available updates:" | tee -a $LOG
dnf check-update 2>&1 | tee -a $LOG || true  # returns exit code 100 if updates available — not an error

# 2. Check if update includes kernel
KERNEL_UPDATE=$(dnf check-update 2>&1 | grep '^kernel' || echo "none")
echo "$(date): Kernel update: $KERNEL_UPDATE" | tee -a $LOG

# 3. Create VM snapshot BEFORE patching (via govc from jump host)
# (This should be done externally before running this script)

# 4. Apply all patches
echo "$(date): Applying patches..." | tee -a $LOG
dnf update -y 2>&1 | tee -a $LOG

# 5. Check if reboot required
REBOOT_NEEDED=$(needs-restarting -r 2>&1 || echo "reboot required")
echo "$(date): Reboot needed: $REBOOT_NEEDED" | tee -a $LOG

# 6. For non-K8s VMs: reboot
# For K8s nodes: drain first, reboot, uncordon (see K8s patch section)
if [[ "$HOSTNAME" != k8s-* ]]; then
  echo "$(date): Rebooting in 30 seconds..." | tee -a $LOG
  sleep 30
  reboot
fi

echo "$(date): Patch complete (reboot pending if K8s node)" | tee -a $LOG
```

### Ansible Playbook — Patch All Non-K8s VMs

```yaml
# patch-vms.yml
- name: Patch Oracle Linux 9 VMs
  hosts: db_vms:service_vms:infra_vms
  become: yes
  serial: 1   # One VM at a time — no parallel patching
  tasks:
    - name: Check for updates
      command: dnf check-update
      register: updates
      failed_when: updates.rc not in [0, 100]
      changed_when: updates.rc == 100

    - name: Apply patches
      dnf:
        name: "*"
        state: latest
      register: patch_result

    - name: Check if reboot needed
      command: needs-restarting -r
      register: reboot_check
      failed_when: false
      changed_when: false

    - name: Reboot if required
      reboot:
        reboot_timeout: 300
        post_reboot_delay: 30
      when: reboot_check.rc == 1

    - name: Verify VM is back
      wait_for_connection:
        timeout: 120

    - name: Verify services running
      service:
        name: "{{ item }}"
        state: started
      loop:
        - chronyd
        - sshd
        - vmtoolsd
```

---

### Kubernetes Node Patching Procedure

> **Rule:** Patch one node at a time. Never drain more than 1 worker per environment simultaneously.

```bash
#!/bin/bash
# k8s-node-patch.sh — Patch a single K8s node safely
# Usage: k8s-node-patch.sh <node-name>
# Example: k8s-node-patch.sh k8s-worker-1

NODE=${1:?"Usage: $0 <node-name>"}

echo "=== K8s Node Patch: $NODE ==="

# Step 1: Cordon (prevent new pods scheduling on this node)
kubectl cordon $NODE
echo "Node $NODE cordoned"

# Step 2: Drain (evict all pods gracefully)
kubectl drain $NODE \
  --ignore-daemonsets \   # DaemonSet pods stay (node-exporter, calico, etc.)
  --delete-emptydir-data \
  --grace-period=60 \     # give pods 60 seconds to terminate gracefully
  --timeout=300s
echo "Node $NODE drained"

# Wait for all pods to evict
sleep 10
REMAINING=$(kubectl get pods --all-namespaces --field-selector spec.nodeName=$NODE \
  --no-headers | grep -v DaemonSet | wc -l)
echo "Remaining pods on $NODE: $REMAINING"

# Step 3: SSH to node and apply patches
ssh oracle@$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') \
  'sudo dnf update -y && sudo reboot'

echo "Patching initiated, waiting for node to come back..."

# Step 4: Wait for node to come back
sleep 60
kubectl wait --for=condition=Ready node/$NODE --timeout=300s
echo "Node $NODE is Ready again"

# Step 5: Verify node is healthy
kubectl describe node $NODE | grep -E "Ready|DiskPressure|MemoryPressure|PIDPressure"

# Step 6: Uncordon
kubectl uncordon $NODE
echo "Node $NODE uncordoned — ready to accept pods"

# Step 7: Verify pods reschedule
sleep 30
kubectl get pods --all-namespaces -o wide | grep $NODE
echo "=== Patch complete for $NODE ==="
```

---

### Kubernetes Version Upgrade (Minor Version)

> **Process:** Upgrade kubeadm → upgrade control plane → upgrade kubelet on each node
> **Example:** Upgrading from K8s 1.29.x to 1.30.x

```bash
# === PHASE 1: Upgrade first control plane master ===
# SSH to k8s-master-1

# 1. Update kubeadm
dnf update -y kubeadm --disableexcludes=kubernetes
kubeadm version  # verify new version

# 2. Check upgrade plan
kubeadm upgrade plan
# Shows: recommended upgrade path and any warnings

# 3. Apply upgrade (this upgrades control plane components)
kubeadm upgrade apply v1.30.0 --yes
# Takes 5-10 minutes — upgrades API server, scheduler, controller manager

# 4. Upgrade kubelet on master-1
kubectl drain k8s-master-1 --ignore-daemonsets --delete-emptydir-data
dnf update -y kubelet kubectl --disableexcludes=kubernetes
systemctl daemon-reload
systemctl restart kubelet
kubectl uncordon k8s-master-1

# 5. Verify master-1
kubectl get nodes
# k8s-master-1 should show new version

# === PHASE 2: Upgrade remaining masters ===
# SSH to k8s-master-2, then k8s-master-3:
kubeadm upgrade node  # (not "apply" — only for first master)
kubectl drain k8s-master-2 --ignore-daemonsets --delete-emptydir-data
dnf update -y kubelet kubectl --disableexcludes=kubernetes
systemctl daemon-reload && systemctl restart kubelet
kubectl uncordon k8s-master-2
# Repeat for master-3

# === PHASE 3: Upgrade each worker (use k8s-node-patch.sh pattern) ===
for WORKER in k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4 k8s-worker-5 k8s-worker-6; do
  echo "Upgrading $WORKER..."
  kubectl drain $WORKER --ignore-daemonsets --delete-emptydir-data --grace-period=60
  
  ssh oracle@$(kubectl get node $WORKER -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}') \
    'sudo kubeadm upgrade node && sudo dnf update -y kubelet kubectl --disableexcludes=kubernetes && sudo systemctl daemon-reload && sudo systemctl restart kubelet'
  
  kubectl wait --for=condition=Ready node/$WORKER --timeout=120s
  kubectl uncordon $WORKER
  echo "$WORKER upgraded"
  sleep 30  # let pods reschedule before moving to next node
done

# Final verification
kubectl get nodes
# All nodes should show new version
```

---

### VxRail / ESXi Patching

> **NEVER patch ESXi hosts directly with esxcli or VMware Update Manager bypassing VxRail Manager.**  
> **VxRail Manager must orchestrate all patches to maintain cluster integrity.**

```
VxRail Patching Process (Via VxRail Manager):

1. Open VxRail Manager: https://vxrail-manager.internal.company.com
   
2. Navigate: Update → Check for Updates
   → VxRail Manager connects to Dell's update catalog
   → Shows available bundle: VxRail 8.x.x (includes ESXi, firmware, drivers)

3. Review What's Included:
   → ESXi patch level
   → iDRAC firmware
   → NIC/HBA driver updates
   → vSAN health patches
   → Review release notes for any breaking changes

4. Schedule Update:
   → Choose "Rolling Update" (one host at a time, VMs live migrate away first)
   → Never choose "Parallel Update" in production
   → Schedule: Saturday 01:00 IST
   → Email notification: your-team@company.com

5. VxRail Manager Update Process (per node, automated):
   a. Move VMs off the host (vSphere vMotion)
   b. Put host in maintenance mode
   c. Apply ESXi patch + firmware update
   d. Reboot host
   e. Host rejoins cluster
   f. vSAN resyncs any objects
   g. Move to next host

6. Verify After Update:
   → All 6 nodes: Connected, Not in maintenance mode
   → vSAN: Healthy, no resync in progress
   → kubectl get nodes: All K8s nodes Ready
```

---

### Patch Compliance Report

```bash
#!/bin/bash
# patch-report.sh — Check patch level on all VMs

REPORT_FILE=/tmp/patch-report-$(date +%Y%m%d).txt
echo "Patch Compliance Report - $(date)" > $REPORT_FILE
echo "==========================================" >> $REPORT_FILE

# Get all VMs from Ansible inventory
VMSLIST=(
  dns-server-01 jump-host veeam-server-01
  k8s-master-1 k8s-master-2 k8s-master-3
  k8s-worker-1 k8s-worker-2 k8s-worker-3 k8s-worker-4 k8s-worker-5 k8s-worker-6
  db-dev-01 db-qa-01 db-preprod-01 db-prod-01
  mongo-dev-01 mongo-qa-01 mongo-preprod-01 mongo-prod-01
  harbor-01 minio-01 monitoring-01
)

for VM in "${VMSLIST[@]}"; do
  echo "" >> $REPORT_FILE
  echo "VM: $VM" >> $REPORT_FILE
  ssh oracle@$VM "
    echo '  OS: ' \$(cat /etc/oracle-release)
    echo '  Kernel: ' \$(uname -r)
    echo '  Last dnf update: ' \$(rpm -qa --last 2>/dev/null | head -1)
    echo '  Pending updates: ' \$(dnf check-update 2>/dev/null | tail -1)
  " 2>/dev/null >> $REPORT_FILE || echo "  ERROR: Could not SSH to $VM" >> $REPORT_FILE
done

echo "" >> $REPORT_FILE
echo "Report complete. See: $REPORT_FILE"
cat $REPORT_FILE
```

