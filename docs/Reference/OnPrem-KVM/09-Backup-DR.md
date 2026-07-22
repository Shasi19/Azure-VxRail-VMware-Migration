# 09 — Backup and Disaster Recovery (KVM)

> **Goal**: Configure Velero (K8s backup), Bacula (file backup), KVM VM snapshots, and etcd backup.  
> KVM provides a unique DR capability: snapshot entire VMs before risky changes.

---

## 1. Velero — Kubernetes Namespace Backup

Velero backs up K8s resource definitions and persistent volume data to MinIO.

### 1a. Install Velero with MinIO Backend

```bash
# Download Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/latest/download/velero-v1.13.0-linux-amd64.tar.gz
tar xvf velero-*.tar.gz
mv velero-*/velero /usr/local/bin/
chmod +x /usr/local/bin/velero

# Create MinIO credentials file
cat > /tmp/velero-credentials << 'EOF'
[default]
aws_access_key_id = minioadmin
aws_secret_access_key = MinIO-OnPrem-2026!
EOF

# Install Velero (using the AWS plugin for S3/MinIO compatibility)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket velero-backups \
  --secret-file /tmp/velero-credentials \
  --backup-location-config \
    region=onprem,s3ForcePathStyle=true,s3Url=http://10.0.1.30:9000 \
  --use-volume-snapshots=false \
  --namespace velero \
  --use-node-agent

# Verify Velero is running
kubectl get pods -n velero
velero backup-location get
```

### 1b. Schedule Regular Backups

```bash
# Daily backup of prod namespace (at 2am UTC)
velero schedule create prod-daily \
  --schedule "0 2 * * *" \
  --include-namespaces prod \
  --ttl 720h0m0s     # 30 days retention

# Daily backup of preprod (at 3am)
velero schedule create preprod-daily \
  --schedule "0 3 * * *" \
  --include-namespaces preprod \
  --ttl 336h0m0s     # 14 days retention

# Weekly backup of all namespaces (Sunday 4am)
velero schedule create all-weekly \
  --schedule "0 4 * * 0" \
  --include-namespaces dev,qa,preprod,prod \
  --ttl 2160h0m0s    # 90 days retention

# List schedules
velero schedule get
```

### 1c. Manual Backup and Restore

```bash
# Take manual backup before risky change
velero backup create pre-upgrade-prod \
  --include-namespaces prod \
  --wait

# Check backup status
velero backup describe pre-upgrade-prod
velero backup logs pre-upgrade-prod

# Restore from backup (to same or different namespace)
velero restore create prod-restore \
  --from-backup pre-upgrade-prod \
  --include-namespaces prod \
  --wait

# Restore to a different namespace (e.g., disaster recovery to dr-prod)
velero restore create dr-prod-restore \
  --from-backup prod-daily-20260721 \
  --namespace-mappings prod:dr-prod \
  --wait
```

---

## 2. etcd Backup (K8s Control Plane State)

etcd stores all K8s cluster state. Back it up before every upgrade.

```bash
# Run on k8s-cp-01 (or any control plane node)
# Install etcdctl if not present
apt install -y etcd-client

# Snapshot etcd to disk
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /backup/etcd/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db

# Verify snapshot
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd/etcd-snapshot-*.db --write-out=table

# Copy snapshot to MinIO for off-node storage
mc cp /backup/etcd/etcd-snapshot-*.db onprem/velero-backups/etcd/

# Schedule with cron (every 6 hours)
cat > /etc/cron.d/etcd-backup << 'EOF'
0 */6 * * * root ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /backup/etcd/etcd-$(date +\%Y\%m\%d-\%H\%M\%S).db \
  && find /backup/etcd -mtime +7 -delete
EOF
```

### Restore etcd (Disaster Recovery)

```bash
# Stop kube-apiserver on all control planes
mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/

# Restore etcd from snapshot
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd/etcd-snapshot-YYYYMMDD.db \
  --name k8s-cp-01 \
  --initial-cluster k8s-cp-01=https://10.0.1.10:2380,k8s-cp-02=https://10.0.1.11:2380,k8s-cp-03=https://10.0.1.12:2380 \
  --initial-cluster-token etcd-cluster-restored \
  --initial-advertise-peer-urls https://10.0.1.10:2380 \
  --data-dir /var/lib/etcd-restored

# Swap data directories
mv /var/lib/etcd /var/lib/etcd-old
mv /var/lib/etcd-restored /var/lib/etcd
chown -R etcd:etcd /var/lib/etcd

# Restart kube-apiserver
mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/
```

---

## 3. KVM VM Snapshots (Unique to KVM Setup)

KVM snapshots capture the entire VM state — OS, memory, disk — for instant recovery.

### 3a. Pre-Change Snapshot

```bash
# Before any major change, snapshot all VMs on a host
snapshot_all() {
  local LABEL=$1
  for VM in $(virsh list --name); do
    virsh snapshot-create-as \
      --domain "$VM" \
      --name "${LABEL}-$(date +%Y%m%d-%H%M)" \
      --description "$LABEL snapshot" \
      --disk-only \
      --atomic
    echo "Snapshot created: $VM - $LABEL"
  done
}

# Usage before K8s upgrade
snapshot_all "pre-k8s-upgrade"

# Usage before OS updates
snapshot_all "pre-os-update"
```

### 3b. Rollback VM to Snapshot

```bash
# List snapshots for a VM
virsh snapshot-list k8s-cp-01 --tree

# Revert to a specific snapshot
virsh snapshot-revert k8s-cp-01 "pre-k8s-upgrade-20260720-1430"

# Delete old snapshots (free disk space)
virsh snapshot-delete k8s-cp-01 "pre-k8s-upgrade-20260601-0900"
```

### 3c. Automated Weekly VM Snapshots

```bash
cat > /usr/local/bin/weekly-vm-snapshot.sh << 'SCRIPT'
#!/bin/bash
LABEL="weekly-$(date +%Y%W)"
for VM in $(virsh list --name); do
  virsh snapshot-create-as \
    --domain "$VM" \
    --name "$LABEL" \
    --disk-only \
    --atomic \
    2>&1 && echo "OK: $VM $LABEL" || echo "FAILED: $VM"
done

# Clean snapshots older than 4 weeks
CUTOFF=$(date -d '28 days ago' +%Y%W)
for VM in $(virsh list --name); do
  virsh snapshot-list "$VM" --name | while read SNAP; do
    SNAP_WEEK=$(echo "$SNAP" | grep -oP '\d{6}')
    [[ "$SNAP_WEEK" < "$CUTOFF" ]] && virsh snapshot-delete "$VM" "$SNAP"
  done
done
SCRIPT

chmod +x /usr/local/bin/weekly-vm-snapshot.sh

# Schedule weekly on Sunday at 1am
echo "0 1 * * 0 root /usr/local/bin/weekly-vm-snapshot.sh >> /var/log/vm-snapshots.log 2>&1" \
  > /etc/cron.d/vm-snapshots
```

---

## 4. Bacula — File-Level Backup

Bacula handles traditional file backups of config files, database dumps, and audit logs.

```bash
# Install Bacula Director on infra-db-01
apt install -y bacula-director bacula-sd bacula-console

# Configure Bacula for PostgreSQL dumps
cat > /etc/bacula/bacula-dir.conf << 'EOF'
Director {
  Name = bacula-dir
  DIRport = 9101
  QueryFile = "/etc/bacula/scripts/query.sql"
  WorkingDirectory = "/var/lib/bacula"
  PidDirectory = "/run/bacula"
  Maximum Concurrent Jobs = 10
  Password = "BaculaDir-2026!"
  Messages = Daemon
}

Schedule {
  Name = "NightlySchedule"
  Run = Daily at 23:00
}

Job {
  Name = "BackupPostgresDump"
  Type = Backup
  Client = infra-db-01-fd
  FileSet = "PostgresDump"
  Schedule = "NightlySchedule"
  Storage = MinIOStorage
  Messages = Standard
  Pool = DefaultPool
  Priority = 10
  Write Bootstrap = "/var/lib/bacula/%c.bsr"
  RunBeforeJob = "/etc/bacula/scripts/pg-dump.sh"
}

FileSet {
  Name = "PostgresDump"
  Include {
    Options { compression = GZIP }
    File = /backup/postgres-dumps
    File = /backup/mongodb-dumps
    File = /etc/kubernetes
    File = /etc/patroni
  }
}
EOF

# Pre-backup script to dump all DBs
cat > /etc/bacula/scripts/pg-dump.sh << 'SCRIPT'
#!/bin/bash
DUMP_DIR=/backup/postgres-dumps
DATE=$(date +%Y%m%d-%H%M)
mkdir -p $DUMP_DIR

for DB in devdb qadb preproddb proddb gitlabdb; do
  pg_dump -h localhost -p 5432 -U postgres $DB \
    --format=custom --compress=9 \
    -f $DUMP_DIR/${DB}-${DATE}.dump
done

# MongoDB dump
for DB in dev-cosmos qa-cosmos preprod-cosmos prod-cosmos; do
  mongodump \
    --host localhost:27017 \
    --username admin \
    --password 'MongoAdmin-OnPrem-2026!' \
    --authenticationDatabase admin \
    --db $DB \
    --out /backup/mongodb-dumps/$DATE/
done

# Clean old dumps (keep 7 days)
find $DUMP_DIR -mtime +7 -delete
find /backup/mongodb-dumps -maxdepth 1 -mtime +7 -exec rm -rf {} +
SCRIPT

chmod +x /etc/bacula/scripts/pg-dump.sh

systemctl enable --now bacula-director
```

---

## 5. DR Runbook — Recovery Time Objectives

| Scenario | RTO | RPO | Recovery Method |
|----------|-----|-----|-----------------|
| Single K8s pod failure | Seconds | 0 | K8s self-healing |
| K8s node VM failure | 5 min | 0 | Patroni failover; pod reschedule |
| Control plane VM crash | 15 min | 0 (etcd replicated) | Revert KVM snapshot; restore etcd |
| Full DB cluster failure | 30 min | Last 6h (etcd backup) | Restore from Velero; mongorestore |
| Entire KVM host failure | 1 hour | Last snapshot | Live-migrate VMs; restore from backup |
| Site disaster | 4 hours | Last 24h backup | Restore all from MinIO backups |

---

## 6. Verify Backup Health

```bash
# Velero backup check
velero backup get
velero schedule get
velero backup-location get

# etcd snapshot integrity
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd/etcd-snapshot-latest.db --write-out=table

# KVM snapshots
for VM in $(virsh list --name); do
  echo "$VM: $(virsh snapshot-list $VM | tail -3)"
done

# MinIO backup buckets
mc ls onprem/velero-backups
mc du onprem/velero-backups

echo "Backup health check complete"
```

---

*KVM setup complete! For application migration from Azure, see: [../Volume-2-Migration-Strategy/](../Volume-2-Migration-Strategy/)*
