# 10 — OLVM Backup

> Covers VM backup via OLVM Export Domain, engine database backup (engine-backup), snapshot schedules, and external backup tools.

---

## OLVM Backup Overview

```
What to back up:
├── OLVM Engine Database    → engine-backup tool → NFS/MinIO
├── VM Disk Snapshots       → OLVM Export Domain → NFS share
├── VM OVF exports          → OLVM API → .ova files on NFS
└── VM config XML           → virsh dumpxml → Git or NFS
```

---

## 1. Engine Database Backup (engine-backup)

The OLVM engine stores all VM definitions, host configs, network layouts, and user data in a PostgreSQL database. Back this up daily.

```bash
# Full engine backup (database + config files + certificates)
engine-backup \
  --mode=backup \
  --file=/backup/olvm/engine-$(date +%Y%m%d-%H%M).tar.gz \
  --log=/var/log/ovirt-engine/engine-backup-$(date +%Y%m%d).log

# The backup includes:
# - PostgreSQL dump of engine database
# - /etc/ovirt-engine/ configuration
# - /etc/pki/ovirt-engine/ certificates
# - DWH database (if configured)

# Verify backup
ls -lh /backup/olvm/
file /backup/olvm/engine-*.tar.gz

# Schedule daily at midnight
cat > /etc/cron.d/olvm-engine-backup << 'EOF'
0 0 * * * root engine-backup \
  --mode=backup \
  --file=/backup/olvm/engine-$(date +\%Y\%m\%d).tar.gz \
  --log=/var/log/ovirt-engine/engine-backup-daily.log \
  && find /backup/olvm -mtime +30 -delete
EOF

# Upload to MinIO for off-engine storage
mc mirror /backup/olvm onprem/velero-backups/olvm-engine/
```

### Restore Engine from Backup

```bash
# WARNING: This restores the OLVM engine to the state at backup time
# All changes made after the backup will be lost

# Stop engine
systemctl stop ovirt-engine

# Restore from backup
engine-backup \
  --mode=restore \
  --file=/backup/olvm/engine-20260721.tar.gz \
  --log=/var/log/ovirt-engine/engine-restore.log \
  --provision-db \          # recreate the DB
  --restore-permissions

# Run engine setup to reconfigure after restore
engine-setup --offline

# Start engine
systemctl start ovirt-engine

echo "OLVM engine restored. Verify at https://olvm-engine.internal/ovirt-engine"
```

---

## 2. VM Snapshot Backup via Export Domain

### 2a. Set Up Export Storage Domain

```
Screenshot: Storage > Domains > New Domain

  Name: export-domain
  Domain Function: Export
  Storage Type: NFS
  Host: kvm-host-01
  Export Path: 10.0.3.10:/vol/olvm_export
  NFS Version: v4.1
  Click OK
```

### 2b. Export a VM to the Export Domain

```
Screenshot: Compute > Virtual Machines > [VM] > right-click > Export

  Export Domain: export-domain
  Force Override: Yes (overwrites previous export of same VM)
  Collapse Snapshots: Yes (merge all snapshots into single disk)
  Click OK

Status bar shows export progress. When complete:
  Status: OK
  VM appears in Storage > Domains > export-domain > Virtual Machines tab
```

### 2c. Export via REST API (Automated)

```bash
VM_NAME="k8s-cp-01"
EXPORT_DOMAIN_ID="<export-domain-uuid>"  # get from OLVM UI or API
VM_ID=$(curl -sk -u admin@internal:OLVMAdmin2026! \
  https://olvm-engine.internal/ovirt-engine/api/vms \
  -H "Accept: application/json" | \
  python3 -c "import sys,json; vms=json.load(sys.stdin)['vm']; \
  [print(v['id']) for v in vms if v['name']=='$VM_NAME']")

curl -sk -u admin@internal:OLVMAdmin2026! \
  -X POST \
  "https://olvm-engine.internal/ovirt-engine/api/vms/${VM_ID}/export" \
  -H "Content-Type: application/json" \
  -d "{
    \"storage_domain\": {\"id\": \"${EXPORT_DOMAIN_ID}\"},
    \"exclusive\": true,
    \"discard_snapshots\": true
  }"

echo "Export started for $VM_NAME"
```

### 2d. Download VM as OVA (for off-site backup)

```bash
# Download exported VM as OVA archive
# First find the OVF path on the NFS export domain
ls /mnt/export-domain/export/<vm-uuid>/

# The export domain contains:
# <vm-uuid>/
#   images/           -- disk images
#   <vm-uuid>.ovf     -- VM configuration in OVF format

# Create an OVA file (tar the export directory)
cd /mnt/export-domain/export/
tar czf /backup/olvm/${VM_NAME}-$(date +%Y%m%d).ova ${VM_UUID}/

# Upload to MinIO
mc cp /backup/olvm/${VM_NAME}-*.ova onprem/velero-backups/olvm-vms/
```

---

## 3. OLVM Scheduled Snapshot Policies

```
Screenshot: Compute > Virtual Machines > [VM] > Snapshots tab > Create Snapshot

Manual snapshot:
  Description: pre-upgrade-$(date +%Y%m%d)
  Save Memory: No (disk-only is faster)
  Click OK

OLVM snapshot = point-in-time consistent disk snapshot
VM continues running during disk-only snapshot creation
```

```bash
# Automate snapshots via OLVM API
cat > /usr/local/bin/olvm-snapshot-all.sh << 'SCRIPT'
#!/bin/bash
API="https://olvm-engine.internal/ovirt-engine/api"
AUTH="admin@internal:OLVMAdmin2026!"
LABEL="scheduled-$(date +%Y%m%d-%H%M)"

# Get all running VMs
VM_IDS=$(curl -sk -u "$AUTH" "$API/vms" -H "Accept: application/json" | \
  python3 -c "import sys,json; vms=json.load(sys.stdin).get('vm',[]); \
  [print(v['id']) for v in (vms if isinstance(vms,list) else [vms]) if v.get('status')=='up']")

for VM_ID in $VM_IDS; do
  VM_NAME=$(curl -sk -u "$AUTH" "$API/vms/$VM_ID" -H "Accept: application/json" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
  
  curl -sk -u "$AUTH" \
    -X POST "$API/vms/$VM_ID/snapshots" \
    -H "Content-Type: application/json" \
    -d "{\"description\": \"$LABEL\", \"persist_memorystate\": false}" > /dev/null
  
  echo "Snapshot created: $VM_NAME ($LABEL)"
done
SCRIPT

chmod +x /usr/local/bin/olvm-snapshot-all.sh

# Schedule weekly snapshot
echo "0 2 * * 0 root /usr/local/bin/olvm-snapshot-all.sh >> /var/log/olvm-snapshots.log" \
  > /etc/cron.d/olvm-snapshots
```

---

## 4. Restore a VM from Backup

### 4a. Restore from Export Domain

```
Screenshot: Storage > Domains > export-domain > Virtual Machines tab

  Select the VM to restore
  Click "Import" button

  In the Import VM dialog:
    Target Cluster: OnPrem-Cluster
    Target Storage Domain: netapp-data
    Collapse Snapshots: Yes (restore as single clean disk)
    Click OK

  The VM is imported and appears in Compute > Virtual Machines
  Start it: click the Run (▶) button
```

### 4b. Restore from OVA File

```bash
# Upload OVA back to export domain
tar xzf /backup/olvm/k8s-cp-01-20260721.ova -C /mnt/export-domain/export/

# Refresh the export storage domain in OLVM UI:
# Storage > Domains > export-domain > right-click > Refresh
# Then follow 4a above to import
```

---

## 5. Backup Monitoring and Health

```bash
cat > /usr/local/bin/olvm-backup-check.sh << 'SCRIPT'
#!/bin/bash
echo "=== OLVM Backup Health Check $(date) ==="

echo "--- Engine backups (last 7 days) ---"
find /backup/olvm -name "engine-*.tar.gz" -mtime -7 | sort | tail -5
find /backup/olvm -name "engine-*.tar.gz" -mtime -7 | wc -l

echo "--- Export domain VM count ---"
ls /mnt/export-domain/export/ 2>/dev/null | wc -l

echo "--- Backup disk usage ---"
df -h /backup/olvm
mc du onprem/velero-backups/olvm-engine/ 2>/dev/null

echo "--- Engine service status ---"
systemctl is-active ovirt-engine && echo "Engine: RUNNING" || echo "Engine: DOWN"

echo "=== Check complete ==="
SCRIPT

chmod +x /usr/local/bin/olvm-backup-check.sh

# Run daily
echo "0 8 * * * root /usr/local/bin/olvm-backup-check.sh >> /var/log/olvm-backup-health.log" \
  >> /etc/cron.d/olvm-backup-health
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `engine-backup` fails | Disk full | Free space in `/backup/olvm`; check `df -h` |
| Export domain inactive | NFS mount failed | `showmount -e 10.0.3.10`; check NFS export policy |
| VM export stuck at 0% | VM has unsupported device | Shut down VM; retry with disk-only snapshot |
| Restore fails "incompatible cluster" | CPU model mismatch | Change target cluster CPU compatibility in OLVM before import |
| "Disk not found" after restore | Storage domain not attached | Re-attach storage domain in OLVM Data Center configuration |

---

*Next: [11-Monitoring-Logging.md](11-Monitoring-Logging.md)*
