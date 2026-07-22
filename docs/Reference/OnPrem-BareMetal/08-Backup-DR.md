# 08 — Backup and Disaster Recovery (Bare-Metal)

> **Goal**: Configure Velero (K8s backup to MinIO), Bacula (file backup), and etcd snapshots.  
> Unlike KVM, there are no VM snapshots — Kubernetes self-healing and Velero restores are the primary DR mechanisms.

---

## 1. Velero — Kubernetes Namespace Backup

### 1a. Install Velero

```bash
wget https://github.com/vmware-tanzu/velero/releases/latest/download/velero-v1.13.0-linux-amd64.tar.gz
tar xvf velero-*.tar.gz
mv velero-*/velero /usr/local/bin/
chmod +x /usr/local/bin/velero

cat > /tmp/velero-credentials << 'EOF'
[default]
aws_access_key_id = minioadmin
aws_secret_access_key = MinIO-OnPrem-2026!
EOF

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

kubectl get pods -n velero
velero backup-location get
```

### 1b. Schedule Backups

```bash
# Production — daily at 2am
velero schedule create prod-daily \
  --schedule "0 2 * * *" \
  --include-namespaces prod \
  --ttl 720h0m0s

# Pre-prod — daily at 3am (14 day retention)
velero schedule create preprod-daily \
  --schedule "0 3 * * *" \
  --include-namespaces preprod \
  --ttl 336h0m0s

# All envs — weekly Sunday 4am (90 day retention)
velero schedule create all-weekly \
  --schedule "0 4 * * 0" \
  --include-namespaces dev,qa,preprod,prod \
  --ttl 2160h0m0s

velero schedule get
```

### 1c. Backup and Restore Commands

```bash
# Manual backup before any change
velero backup create pre-upgrade-prod \
  --include-namespaces prod \
  --wait

# Check status
velero backup describe pre-upgrade-prod --details
velero backup logs pre-upgrade-prod

# Restore to same namespace
velero restore create restore-prod \
  --from-backup pre-upgrade-prod \
  --include-namespaces prod \
  --wait

# Restore to DR namespace
velero restore create restore-to-dr \
  --from-backup prod-daily-20260721 \
  --namespace-mappings prod:prod-dr \
  --wait

# Describe restore progress
velero restore describe restore-prod
```

---

## 2. etcd Backup (K8s Control Plane)

```bash
# Install etcdctl
apt install -y etcd-client

# Create backup directory
mkdir -p /backup/etcd

# Take snapshot (run on any control plane server)
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /backup/etcd/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db

# Verify
ETCDCTL_API=3 etcdctl snapshot status \
  /backup/etcd/etcd-snapshot-*.db \
  --write-out=table

# Upload to MinIO
mc cp /backup/etcd/etcd-snapshot-*.db onprem/velero-backups/etcd/

# Cron: every 6 hours
cat > /etc/cron.d/etcd-backup << 'EOF'
0 */6 * * * root ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /backup/etcd/etcd-$(date +\%Y\%m\%d-\%H\%M).db \
  && find /backup/etcd -mtime +7 -delete
EOF
```

### Restore etcd After Cluster Failure

```bash
# Stop apiserver on ALL control plane servers
for CP in 10.0.1.10 10.0.1.11 10.0.1.12; do
  ssh admin@$CP "sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/"
done

# Restore from snapshot (on each control plane with its own peer URL)
# On server-cp-01:
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd/etcd-snapshot-YYYYMMDD.db \
  --name server-cp-01 \
  --initial-cluster "server-cp-01=https://10.0.1.10:2380,server-cp-02=https://10.0.1.11:2380,server-cp-03=https://10.0.1.12:2380" \
  --initial-cluster-token etcd-restored \
  --initial-advertise-peer-urls https://10.0.1.10:2380 \
  --data-dir /var/lib/etcd-restored

mv /var/lib/etcd /var/lib/etcd-old
mv /var/lib/etcd-restored /var/lib/etcd

# Start apiserver back
mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/
kubectl get nodes
```

---

## 3. Bacula — Database File Backup

```bash
apt install -y bacula-director bacula-sd bacula-console

# Pre-backup script: dump all DBs
cat > /etc/bacula/scripts/dump-all.sh << 'SCRIPT'
#!/bin/bash
DATE=$(date +%Y%m%d-%H%M)
PG_DUMP_DIR=/backup/postgres
MONGO_DUMP_DIR=/backup/mongodb

mkdir -p $PG_DUMP_DIR $MONGO_DUMP_DIR

# PostgreSQL dumps
for DB in devdb qadb preproddb proddb gitlabdb; do
  pg_dump -h localhost -p 5432 -U postgres $DB \
    --format=custom --compress=9 \
    -f $PG_DUMP_DIR/${DB}-${DATE}.dump
done

# MongoDB dumps
for DB in dev-cosmos qa-cosmos preprod-cosmos prod-cosmos; do
  mongodump \
    --host 10.0.1.30,10.0.1.31,10.0.1.32 \
    --replicaSet rs-prod \
    --username admin \
    --password 'MongoAdmin-OnPrem-2026!' \
    --authenticationDatabase admin \
    --db $DB \
    --out $MONGO_DUMP_DIR/$DATE/

  # Compress the dump
  tar czf $MONGO_DUMP_DIR/${DB}-${DATE}.tar.gz $MONGO_DUMP_DIR/$DATE/$DB
  rm -rf $MONGO_DUMP_DIR/$DATE
done

# Copy to MinIO
mc mirror /backup/postgres onprem/db-backups/postgres/
mc mirror /backup/mongodb onprem/db-backups/mongodb/

# Cleanup local (keep 3 days locally)
find $PG_DUMP_DIR -mtime +3 -delete
find $MONGO_DUMP_DIR -mtime +3 -delete
SCRIPT

chmod +x /etc/bacula/scripts/dump-all.sh

# Schedule via cron (run nightly at 11pm)
echo "0 23 * * * root /etc/bacula/scripts/dump-all.sh >> /var/log/db-backup.log 2>&1" \
  > /etc/cron.d/db-backup
```

---

## 4. Bare-Metal Node Recovery

Unlike KVM (no VM snapshot rollback), bare-metal uses drain-and-replace:

```bash
# Step 1: Mark node as unschedulable and evict pods
kubectl drain server-wk-05 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --grace-period=120

# Step 2: Remove from cluster
kubectl delete node server-wk-05

# Step 3: Re-provision the server (reinstall OS if needed)
# Then on the server, run the fresh join token:
kubeadm token create --print-join-command
# Run the output on the repaired server

# Step 4: Re-label the rejoined node
kubectl label node server-wk-05 env=prod workload=app
kubectl taint nodes server-wk-05 env=prod:NoSchedule
```

---

## 5. PostgreSQL Point-in-Time Recovery (PITR)

```bash
# Configure WAL archiving to MinIO (add to Patroni postgresql.parameters)
# wal_archive_command = 'mc cp %p onprem/db-backups/wal/%f'
# archive_mode = on
# archive_command = ...

# Restore to a specific point in time
pg_restore \
  -h 10.0.1.30 \
  -p 5432 \
  -U postgres \
  -d proddb_recovery \
  --format=custom \
  /backup/postgres/proddb-20260720-2300.dump

# Connect to recovery DB and verify
psql -h 10.0.1.30 -U postgres -d proddb_recovery \
  -c "SELECT count(*) FROM critical_table;"
```

---

## 6. DR Runbook — RTO/RPO Targets

| Scenario | RTO | RPO | Recovery Method |
|----------|-----|-----|-----------------|
| Single pod crash | Seconds | 0 | K8s self-healing |
| Worker node hardware failure | 10 min | 0 | Drain, replace, rejoin |
| PostgreSQL primary failure | 30 sec | 0 | Patroni automatic failover |
| MongoDB primary failure | 10 sec | 0 | RS automatic election |
| K8s namespace corruption | 30 min | Last backup | `velero restore` |
| K8s cluster total failure | 2 hours | Last etcd snapshot | Reinstall K8s, restore etcd |
| DB cluster total loss | 4 hours | Last nightly dump | mongorestore + pg_restore |
| Site disaster | 8 hours | Last nightly backup | Full rebuild from MinIO backups |

---

## 7. Backup Health Monitoring

```bash
cat > /usr/local/bin/check-backups.sh << 'SCRIPT'
#!/bin/bash
echo "=== Backup Health Check $(date) ==="

echo "--- Velero backups ---"
velero backup get | grep -E '(Completed|Failed|InProgress)'

echo "--- Latest etcd snapshot ---"
ls -lh /backup/etcd/ | tail -3

echo "--- PostgreSQL dumps (last 24h) ---"
find /backup/postgres -mtime -1 -name "*.dump" | wc -l

echo "--- MongoDB dumps (last 24h) ---"
find /backup/mongodb -mtime -1 -name "*.tar.gz" | wc -l

echo "--- MinIO backup bucket size ---"
mc du onprem/velero-backups
mc du onprem/db-backups

echo "=== Check complete ==="
SCRIPT

chmod +x /usr/local/bin/check-backups.sh

# Run daily at 8am and log to monitoring
echo "0 8 * * * root /usr/local/bin/check-backups.sh >> /var/log/backup-health.log" \
  >> /etc/cron.d/backup-health
```

---

*Bare-metal setup complete! For application migration from Azure, see: [../Volume-2-Migration-Strategy/](../Volume-2-Migration-Strategy/)*
