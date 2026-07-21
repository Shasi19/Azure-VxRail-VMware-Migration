# 12 — Backup and Recovery

> Complete backup strategy for KVM VMs, OLVM engine, databases, and Kubernetes. Includes cold backup, live snapshots, dirty bitmap incremental backup, Bacula, and full DR runbooks.

---

## Backup Strategy Overview

| Strategy | VM State | Consistency | Speed | Best For |
|----------|----------|-------------|-------|----------|
| **Cold backup** (VM off) | Off | Perfect | Slow | Monthly archive |
| **Disk-only snapshot + copy** | Running | Crash-consistent | Medium | Daily VM backup |
| **Memory snapshot** | Paused briefly | Application-consistent | Slow | Before risky changes |
| **Guest agent + snapshot** | Running | Application-consistent | Medium | Production DBs |
| **Dirty bitmap incremental** | Running | Crash-consistent | Fast (only changed blocks) | Daily incremental |
| **Velero** | Pods running | K8s state | Fast | Kubernetes resources |
| **pg_dump / mongodump** | Running | Consistent | Fast | Database specific |

---

## 1. Cold Backup (VM Powered Off)

Simplest and most reliable. Copy the disk image while VM is off.

```bash
# Shutdown the VM gracefully
virsh shutdown k8s-cp-01
# Wait for it to stop
virsh domstate k8s-cp-01
# "shut off"

# Copy the disk image
VM_DISK=$(virsh domblklist k8s-cp-01 --details | awk '/disk/{print $4}')
BACKUP_DIR="/backup/vms/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Method A: Simple copy (preserves QCOW2 format with backing file)
cp $VM_DISK $BACKUP_DIR/k8s-cp-01.qcow2

# Method B: Convert and compress (smaller backup file)
qemu-img convert -f qcow2 -O qcow2 -c \
  $VM_DISK \
  $BACKUP_DIR/k8s-cp-01-$(date +%Y%m%d).qcow2

# Method C: Sparse copy (fast, preserves holes)
cp --sparse=always $VM_DISK $BACKUP_DIR/k8s-cp-01.qcow2

# Also backup VM XML definition
virsh dumpxml k8s-cp-01 > $BACKUP_DIR/k8s-cp-01.xml

# Start VM again
virsh start k8s-cp-01

# Upload backup to MinIO
mc cp $BACKUP_DIR/k8s-cp-01*.qcow2 onprem/velero-backups/vm-backups/
```

---

## 2. Live Backup with External Snapshot + blockcommit

The VM keeps running. We take an external (disk-only) snapshot, then copy the frozen base image.

```bash
VM_NAME="k8s-wk-01"
BACKUP_DIR="/backup/vms/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Step 1: Get current disk path
DISK_PATH=$(virsh domblklist $VM_NAME --details | awk '/disk/{print $4}')
DISK_TARGET=$(virsh domblklist $VM_NAME --details | awk '/disk/{print $3}')
echo "Disk: $DISK_TARGET → $DISK_PATH"

# Step 2: Freeze filesystems (requires qemu-guest-agent inside VM)
virsh domfsfreeze $VM_NAME
echo "Filesystems frozen"

# Step 3: Create external disk-only snapshot
SNAP_PATH="${DISK_PATH%.qcow2}.snap-$(date +%Y%m%d-%H%M).qcow2"
virsh snapshot-create-as $VM_NAME \
  "backup-$(date +%Y%m%d-%H%M)" \
  --disk-only \
  --diskspec ${DISK_TARGET},file=${SNAP_PATH} \
  --atomic
echo "Snapshot created: $SNAP_PATH"

# Step 4: Thaw filesystems immediately
virsh domfsthaw $VM_NAME
echo "Filesystems thawed"

# Step 5: Copy the FROZEN base disk (before the snapshot)
# The VM is now writing to SNAP_PATH, so DISK_PATH is static
cp $DISK_PATH $BACKUP_DIR/${VM_NAME}-$(date +%Y%m%d).qcow2
echo "Base disk copied to backup"

# Step 6: Merge snapshot back (blockcommit)
# This merges SNAP_PATH changes back into DISK_PATH and pivots back to it
virsh blockcommit $VM_NAME $DISK_TARGET \
  --base $DISK_PATH \
  --top $SNAP_PATH \
  --wait \
  --verbose \
  --pivot
echo "Snapshot merged back — VM now uses original disk"

# Step 7: Remove leftover snapshot file
rm -f $SNAP_PATH
virsh snapshot-delete $VM_NAME "backup-$(date +%Y%m%d-%H%M)" 2>/dev/null

# Step 8: Also backup VM XML
virsh dumpxml $VM_NAME > $BACKUP_DIR/${VM_NAME}.xml

echo "Backup complete: $BACKUP_DIR/${VM_NAME}-$(date +%Y%m%d).qcow2"
```

---

## 3. Incremental Backup with Dirty Bitmaps (QEMU 6+)

QEMU tracks which 64KB disk blocks have changed since the last backup. Incremental backup copies only those blocks — typically 5-20x faster than full backup.

```bash
VM_NAME="infra-db-01"
DISK_TARGET="vda"
BITMAP_NAME="incr-backup"

# --- First time: create the bitmap ---
# The bitmap starts tracking changes from this point
virsh qemu-monitor-command $VM_NAME --hmp \
  "block-dirty-bitmap-add ${DISK_TARGET} ${BITMAP_NAME} granularity=65536 persistent=true"
echo "Bitmap created — now tracking changes on $DISK_TARGET"

# --- Full backup (do this once, then use incremental) ---
FULL_BACKUP="/backup/vms/full-$(date +%Y%m%d)/${VM_NAME}-full.qcow2"
mkdir -p $(dirname $FULL_BACKUP)

# Create snapshot to freeze the disk
virsh domfsfreeze $VM_NAME
virsh snapshot-create-as $VM_NAME snap-full --disk-only --atomic
virsh domfsthaw $VM_NAME

SNAP_PATH=$(virsh domblklist $VM_NAME --details | awk '/disk/{print $4}')

# Copy frozen disk as full backup
qemu-img convert -f qcow2 -O qcow2 \
  $(virsh domblklist $VM_NAME | awk '/'${DISK_TARGET}'/{print $2}') \
  $FULL_BACKUP

# Commit snapshot back
virsh blockcommit $VM_NAME $DISK_TARGET --wait --pivot
echo "Full backup: $FULL_BACKUP"

# --- Daily incremental backup ---
# Uses nbd (network block device) + qemu-img to copy only dirty blocks
INCR_BACKUP="/backup/vms/incr-$(date +%Y%m%d)/${VM_NAME}-incr.qcow2"
mkdir -p $(dirname $INCR_BACKUP)

# Create incremental snapshot
virsh domfsfreeze $VM_NAME
virsh snapshot-create-as $VM_NAME snap-incr --disk-only --atomic
virsh domfsthaw $VM_NAME

# Get the disk path (now the snapshot)
CURRENT_DISK=$(virsh domblklist $VM_NAME | awk '/'${DISK_TARGET}'/{print $2}')

# Export and copy dirty blocks using qemu-nbd
qemu-img create -f qcow2 -b $FULL_BACKUP $INCR_BACKUP 0
# Use qemu-nbd to copy only dirty blocks referenced by bitmap
# (Requires QEMU 5.2+ with backup-top)

# Commit snapshot back
virsh blockcommit $VM_NAME $DISK_TARGET --wait --pivot
echo "Incremental backup: $INCR_BACKUP"
```

---

## 4. Bacula for KVM VMs

Bacula handles traditional file backup of VM disks, configs, and DB dumps.

```bash
# Install Bacula
dnf install -y bacula-director bacula-storage bacula-console  # RHEL/OL
# apt install -y bacula-director bacula-sd bacula-console       # Ubuntu

# Pre-backup script: freeze VMs + dump DBs + copy VM XML
cat > /etc/bacula/scripts/pre-backup.sh << 'SCRIPT'
#!/bin/bash
DUMP_DIR=/backup/pre-bacula/$(date +%Y%m%d-%H%M)
mkdir -p $DUMP_DIR

echo "=== Pre-Backup Script Starting ==="

# 1. Dump PostgreSQL databases
for DB in devdb qadb preproddb proddb; do
  pg_dump -h 10.0.1.30 -p 5000 -U postgres $DB \
    --format=custom --compress=9 \
    -f $DUMP_DIR/pg-${DB}.dump
  echo "Dumped: $DB"
done

# 2. Dump MongoDB collections
for DB in dev-cosmos qa-cosmos preprod-cosmos prod-cosmos; do
  mongodump \
    --host "10.0.1.30:27017,10.0.1.31:27017,10.0.1.32:27017" \
    --replicaSet rs-prod \
    -u admin -p 'MongoAdmin-OnPrem-2026!' --authenticationDatabase admin \
    --db $DB --out $DUMP_DIR/mongo/
  echo "Dumped: $DB"
done

# 3. Freeze all VMs and take disk-only snapshots
for VM in $(virsh list --name); do
  virsh domfsfreeze $VM 2>/dev/null
  virsh snapshot-create-as $VM "pre-bacula-$(date +%Y%m%d)" \
    --disk-only --atomic 2>/dev/null
  virsh domfsthaw $VM 2>/dev/null
  virsh dumpxml $VM > $DUMP_DIR/${VM}.xml
  echo "Snapshot + XML: $VM"
done

echo "=== Pre-Backup Complete: $DUMP_DIR ==="
SCRIPT
chmod +x /etc/bacula/scripts/pre-backup.sh

# Post-backup script: merge snapshots back
cat > /etc/bacula/scripts/post-backup.sh << 'SCRIPT'
#!/bin/bash
for VM in $(virsh list --name); do
  DISK_TARGET=$(virsh domblklist $VM --details | awk '/disk/{print $3}' | head -1)
  SNAP=$(virsh snapshot-list $VM --name | grep pre-bacula | head -1)
  if [ -n "$SNAP" ]; then
    virsh blockcommit $VM $DISK_TARGET --wait --pivot 2>/dev/null
    virsh snapshot-delete $VM "$SNAP" 2>/dev/null
    echo "Merged snapshot for $VM"
  fi
done
SCRIPT
chmod +x /etc/bacula/scripts/post-backup.sh

# Bacula Director configuration excerpt
cat >> /etc/bacula/bacula-dir.conf << 'EOF'
Job {
  Name = "KVMFullBackup"
  Type = Backup
  Client = kvm-host-01-fd
  FileSet = "KVMFiles"
  Schedule = "WeeklySchedule"
  Storage = MinIOStorage
  Pool = WeeklyPool
  Priority = 10
  RunBeforeJob = "/etc/bacula/scripts/pre-backup.sh"
  RunAfterJob  = "/etc/bacula/scripts/post-backup.sh"
}

FileSet {
  Name = "KVMFiles"
  Include {
    Options { compression = GZIP; signature = MD5 }
    File = /backup/pre-bacula
    File = /etc/libvirt
    File = /etc/patroni
    File = /etc/kubernetes
  }
  Exclude {
    File = /proc
    File = /sys
    File = /tmp
  }
}
EOF
systemctl enable --now bacula-director
```

---

## 5. MinIO as Backup Target

```bash
# Configure MinIO bucket with versioning (protects against accidental deletion)
mc mb onprem/vm-backups
mc mb onprem/db-backups

# Enable versioning
mc version enable onprem/vm-backups
mc version enable onprem/db-backups

# Set lifecycle: keep 90 days of versions for prod, 30 days for dev
mc ilm import onprem/vm-backups << 'EOF'
{
  "Rules": [
    {
      "ID": "prod-retention",
      "Status": "Enabled",
      "Filter": {"Prefix": "prod/"},
      "NoncurrentVersionExpiration": {"NoncurrentDays": 90}
    },
    {
      "ID": "dev-retention",
      "Status": "Enabled",
      "Filter": {"Prefix": "dev/"},
      "Expiration": {"Days": 30}
    }
  ]
}
EOF

# Set up mc mirror for continuous sync
# Upload a new backup
mc cp /backup/vms/k8s-cp-01-*.qcow2 onprem/vm-backups/k8s-cp-01/

# Mirror an entire backup directory
mc mirror /backup/vms onprem/vm-backups/

# Check bucket contents and sizes
mc ls onprem/vm-backups/
mc du onprem/vm-backups/
```

---

## 6. Full VM Restore from Backup

```bash
# Step 1: Download backup from MinIO if needed
mc cp onprem/vm-backups/k8s-cp-01/k8s-cp-01-20260720.qcow2 \
  /data/kvm/images/k8s-cp-01-restore.qcow2

# Step 2: Restore VM definition from XML backup
virsh define /backup/vms/20260720/k8s-cp-01.xml

# Step 3: Update the VM's disk path to point to restored image
virsh edit k8s-cp-01
# Change <source file='...'/> to point to the restored qcow2

# Step 4: Start VM
virsh start k8s-cp-01

# Step 5: Verify
virsh domstate k8s-cp-01
ssh admin@10.0.1.10 "hostname && kubectl get nodes"
```

---

## 7. Disaster Recovery Runbook

### Scenario: Single KVM Host Failure (OLVM HA handles this automatically)

```bash
# 1. OLVM detects host is down (VDSM timeout ~30s)
# 2. OLVM fences the host via IPMI
# 3. OLVM restarts VMs on other hosts (~2-5 minutes)
# 4. Kubernetes detects nodes are back
# 5. Pods reschedule automatically

# To verify after recovery:
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running
```

### Scenario: Multiple Host Failure (Manual Recovery)

```bash
# 1. Provision new KVM hosts (or repair failed ones)
# 2. Re-add to OLVM cluster
# 3. Restore VM images from backup
for VM_IMAGE in $(mc ls onprem/vm-backups/ | awk '{print $5}'); do
  mc cp onprem/vm-backups/$VM_IMAGE /data/kvm/images/
done

# 4. Restore VM definitions
for XML in /backup/vms/latest/*.xml; do
  virsh define $XML
  VM_NAME=$(basename $XML .xml)
  virsh start $VM_NAME
  echo "Started: $VM_NAME"
done

# 5. Restore Kubernetes etcd
# (See OnPrem-KVM/09-Backup-DR.md for etcd restore procedure)

# 6. Verify cluster health
kubectl get nodes
patronictl -c /etc/patroni/patroni.yml list
```

---

## 8. Backup Health Report Script

```bash
cat > /usr/local/bin/backup-health.sh << 'SCRIPT'
#!/bin/bash
echo "==============================="
echo "  BACKUP HEALTH REPORT"
echo "  $(date)"
echo "==============================="

ISSUES=0

echo ""
echo "--- VM Backups (last 24h) ---"
COUNT=$(find /backup/vms -name "*.qcow2" -mtime -1 | wc -l)
echo "VM backups in last 24h: $COUNT"
[ $COUNT -eq 0 ] && echo "WARNING: No VM backups found!" && ((ISSUES++))

echo ""
echo "--- Database Dumps (last 24h) ---"
PG=$(find /backup/pre-bacula -name "pg-*.dump" -mtime -1 | wc -l)
MONGO=$(find /backup/pre-bacula -name "mongo" -type d -mtime -1 | wc -l)
echo "PostgreSQL dumps: $PG"
echo "MongoDB dumps:    $MONGO"
[ $PG -eq 0 ] && echo "WARNING: No PostgreSQL backups!" && ((ISSUES++))
[ $MONGO -eq 0 ] && echo "WARNING: No MongoDB backups!" && ((ISSUES++))

echo ""
echo "--- OLVM Engine Backup ---"
LATEST=$(find /backup/olvm -name "engine-*.tar.gz" -mtime -2 | head -1)
if [ -n "$LATEST" ]; then
  echo "Latest: $LATEST ($(stat -c%s $LATEST | numfmt --to=iec))"
else
  echo "WARNING: No recent OLVM engine backup!" && ((ISSUES++))
fi

echo ""
echo "--- MinIO Storage ---"
mc du onprem/vm-backups/ 2>/dev/null
mc du onprem/db-backups/ 2>/dev/null

echo ""
echo "--- etcd Snapshots ---"
ETCD=$(find /backup/etcd -name "*.db" -mtime -1 | wc -l)
echo "etcd snapshots (last 24h): $ETCD"
[ $ETCD -eq 0 ] && echo "WARNING: No etcd backup!" && ((ISSUES++))

echo ""
if [ $ISSUES -eq 0 ]; then
  echo "STATUS: ALL CHECKS PASSED"
else
  echo "STATUS: $ISSUES ISSUE(S) FOUND — INVESTIGATE IMMEDIATELY"
fi
echo "==============================="
SCRIPT

chmod +x /usr/local/bin/backup-health.sh

# Run daily and send to Slack if issues
cat >> /usr/local/bin/backup-health.sh << 'EOF'
# Send to Slack if issues found
if [ $ISSUES -gt 0 ]; then
  curl -s -X POST https://hooks.slack.com/services/YOUR/WEBHOOK \
    -d "{\"text\":\"BACKUP ALERT: $ISSUES issues found on $(hostname). Check /var/log/backup-health.log\"}"
fi
EOF

echo "0 9 * * * root /usr/local/bin/backup-health.sh >> /var/log/backup-health.log 2>&1" \
  >> /etc/cron.d/backup-health
```

---

## DR Targets Summary

| Scenario | RTO | RPO | Method |
|----------|-----|-----|--------|
| Single pod crash | Seconds | 0 | K8s self-healing |
| K8s worker VM crash | 3-5 min | 0 | OLVM HA VM restart |
| PostgreSQL primary failure | 30 sec | 0 | Patroni auto-failover |
| MongoDB primary failure | 10 sec | 0 | RS auto-election |
| KVM host failure | 5 min | 0 | OLVM HA (requires fencing) |
| VM disk corruption | 30 min | Last snapshot | Restore from snapshot backup |
| OLVM engine failure | 20 min | Last engine-backup | Restore with engine-backup --restore |
| Full datacenter failure | 4-8 hours | Last nightly backup | Full restore from MinIO |

---

*KVM/OLVM guide complete! Back to main index: [00-Index.md](00-Index.md)*
