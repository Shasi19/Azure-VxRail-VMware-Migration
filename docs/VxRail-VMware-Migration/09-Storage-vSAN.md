# Storage Configuration — vSAN + vSphere CSI

## Overview

VxRail's distributed storage (vSAN) provides the persistent volume backend for all Kubernetes workloads and database VMs. The **vSphere CSI driver** bridges Kubernetes PVCs to vSAN-backed VMDKs.

```
Kubernetes PVC
    └── StorageClass (vSphere CSI)
         └── vSphere CSI Controller (in K8s)
              └── Creates VMDK on vSAN Datastore
                   └── Mounted to worker node VM
                        └── Mounted into Pod as PV
```

---

## 1. vSAN Storage Policies

Create policies in vCenter: **Policies and Profiles > VM Storage Policies > Create**

### 1.1 Policy: k8s-dev-qa (no redundancy — saves space)

```
Name: k8s-dev-qa
Rules:
  Tag-based placement: (none)
  Storage rules:
    Host-based rule:
      Number of failures to tolerate (FTT): 0
      Failure tolerance method: RAID-1 (Mirroring)
    Space Efficiency:
      Deduplication and compression: Enabled
```

### 1.2 Policy: k8s-production (FTT=1, survives 1 node failure)

```
Name: k8s-production
Rules:
  Storage rules:
    Host-based rule:
      Number of failures to tolerate (FTT): 1
      Failure tolerance method: RAID-1 (Mirroring)
    Performance:
      IOPS limit per object: 0 (unlimited)
```

### 1.3 Policy: k8s-databases (RAID-5 erasure coding — 4+ nodes needed)

```
Name: k8s-databases
Rules:
  Storage rules:
    Host-based rule:
      Number of failures to tolerate (FTT): 1
      Failure tolerance method: RAID-5/6 (Erasure Coding)
    Performance:
      Flash read cache reservation: 0%
      Disable object checksum: No
```

---

## 2. Install vSphere CSI Driver

The vSphere CSI driver runs inside Kubernetes and provisions PVs as VMDKs on vSAN.

### 2.1 Prerequisites on All K8s VMs

```bash
# On each K8s node VM — disk UUID must be enabled
# Do this BEFORE installing K8s

# Check current setting
govc vm.info -dc="Datacenter" k8s-worker-1 | grep diskUUID

# Enable disk.EnableUUID on each VM (required by vSphere CSI)
# This is done via vCenter UI: VM Settings > Options > Advanced > Configuration Parameters
# Add: disk.EnableUUID = TRUE
# OR via govc:
for VM in k8s-master-1 k8s-master-2 k8s-master-3 \
          k8s-worker-1 k8s-worker-2 k8s-worker-3 \
          k8s-worker-4 k8s-worker-5 k8s-worker-6; do
  govc vm.change -dc="Datacenter" -vm="$VM" \
    -e "disk.EnableUUID=TRUE"
done
```

### 2.2 Create vSphere CSI Service Account in vCenter

```bash
# In vCenter: Administration > Access Control > Roles > New Role
# Role name: csi-vsphere-role
# Privileges needed:
#   Datastore: Allocate space, Browse datastore, Low level file ops
#   Host: Config storage
#   VirtualMachine: Config change, Change settings
#   StorageProfile: View, Update

# Create a dedicated user for CSI:
# Administration > Users and Groups > Users > Add
# Username: k8s-csi-user
# Password: CSIuser2026!
# Assign csi-vsphere-role to this user at Datacenter level
```

### 2.3 Create vSphere CSI Configuration Secret

```bash
# Create vSphere CSI config file on your jump host
cat > /tmp/csi-vsphere.conf << EOF
[Global]
cluster-id = "vxrail-k8s-cluster"

[VirtualCenter "vcenter.internal.company.com"]
insecure-flag = "false"
user = "k8s-csi-user@vsphere.local"
password = "CSIuser2026!"
port = "443"
datacenters = "Datacenter"
EOF

# Create Kubernetes secret from this config
kubectl create namespace vmware-system-csi

kubectl create secret generic vsphere-config-secret \
  --from-file=csi-vsphere.conf=/tmp/csi-vsphere.conf \
  --namespace=vmware-system-csi

# Remove local config file (contains credentials)
rm /tmp/csi-vsphere.conf
```

### 2.4 Deploy vSphere CSI Driver

```bash
# Get the latest release URL
VSPHERE_CSI_VERSION="3.3.0"
CSI_MANIFEST="https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v${VSPHERE_CSI_VERSION}/manifests/vanilla/deploy/vsphere-csi-driver.yaml"

kubectl apply -f "${CSI_MANIFEST}"

# Verify deployment
kubectl get pods -n vmware-system-csi
# Expected: vsphere-csi-controller, vsphere-csi-node (on each node)

kubectl get csidrivers
# Expected: csi.vsphere.volume.max.recoverable.error
```

---

## 3. StorageClasses for Kubernetes

### 3.1 Create StorageClasses Mapped to vSAN Policies

```yaml
# storageclass-vsan.yaml
---
# Dev and QA — no redundancy (saves vSAN space)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsan-dev-qa
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: csi.vsphere.volume
parameters:
  storagepolicyname: "k8s-dev-qa"
  datastoreURL: "ds:///vmfs/volumes/vsan:xxxxxxxx/"   # update with your vSAN UUID
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
# PreProd and Prod — FTT=1 redundancy
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsan-production
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.vsphere.volume
parameters:
  storagepolicyname: "k8s-production"
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
# Databases — RAID-5 erasure coding
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsan-databases
provisioner: csi.vsphere.volume
parameters:
  storagepolicyname: "k8s-databases"
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

```bash
# Get your vSAN datastore URL
govc datastore.info -dc="Datacenter" vsanDatastore | grep URL

kubectl apply -f storageclass-vsan.yaml
kubectl get storageclasses
```

---

## 4. MinIO on vSAN (Replaces Azure Storage Account)

MinIO runs as a single-node container on `minio-01` VM backed by a large vSAN VMDK.

### 4.1 Install MinIO on minio-01

```bash
ssh oracle@10.0.6.11

# Create data directory backed by vSAN disk
sudo mkdir -p /data/minio

# Mount large vSAN disk (if added as second VMDK in vCenter)
lsblk  # identify second disk e.g. /dev/sdb
sudo mkfs.xfs /dev/sdb
echo '/dev/sdb /data/minio xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
sudo mount -a

# Install MinIO
wget https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x minio
sudo mv minio /usr/local/bin/

# Create systemd service
sudo useradd -r -s /bin/false minio
sudo chown minio:minio /data/minio

sudo tee /etc/systemd/system/minio.service << 'EOF'
[Unit]
Description=MinIO
After=network.target

[Service]
User=minio
Group=minio
EnvironmentFile=/etc/minio/minio.env
ExecStart=/usr/local/bin/minio server /data/minio --console-address :9001
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mkdir /etc/minio
sudo tee /etc/minio/minio.env << 'EOF'
MINIO_ROOT_USER=minio-admin
MINIO_ROOT_PASSWORD=MinIO@VxRail2026!
MINIO_VOLUMES=/data/minio
MINIO_SITE_NAME=vxrail-minio
EOF

sudo chmod 600 /etc/minio/minio.env
sudo systemctl daemon-reload
sudo systemctl enable minio
sudo systemctl start minio

# Verify
curl -s http://10.0.6.11:9000/minio/health/live && echo "MinIO running"
```

### 4.2 Create MinIO Buckets per Environment

```bash
# Install mc (MinIO client)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc && sudo mv mc /usr/local/bin/

# Configure alias
mc alias set vxrail http://10.0.6.11:9000 minio-admin MinIO@VxRail2026!

# Create buckets for each environment
mc mb vxrail/dev-storage
mc mb vxrail/qa-storage
mc mb vxrail/preprod-storage
mc mb vxrail/prod-storage
mc mb vxrail/harbor-storage
mc mb vxrail/velero-backup
mc mb vxrail/db-backup

# List buckets
mc ls vxrail
```

### 4.3 Create Kubernetes Secret for MinIO Access

```bash
# Create secret in each namespace
for NS in dev qa preprod prod; do
  kubectl create secret generic minio-credentials \
    --namespace="${NS}" \
    --from-literal=MINIO_ENDPOINT=http://10.0.6.11:9000 \
    --from-literal=MINIO_ACCESS_KEY=minio-admin \
    --from-literal=MINIO_SECRET_KEY=MinIO@VxRail2026! \
    --from-literal=MINIO_BUCKET="${NS}-storage"
done
```

---

## 5. vSAN Performance Monitoring

```bash
# On any ESXi host (SSH)
esxtop -b -d 2 -n 5 | grep vsan

# In vCenter: vSAN > Performance > Virtual Disks
# Key metrics to watch:
#   IOPS: should not constantly hit limits
#   Latency: < 1ms for NVMe vSAN
#   Outstanding I/O: < 32 per device

# Check vSAN health (run periodically)
govc cluster.csnap -dc="Datacenter" VxRail-Cluster
```

---

## 6. Troubleshooting Storage

| Issue | Symptom | Resolution |
|-------|---------|------------|
| PVC stuck Pending | `kubectl describe pvc` shows no suitable node | Check `disk.EnableUUID=TRUE` on all VMs; check CSI controller logs |
| CSI controller CrashLoop | `kubectl logs -n vmware-system-csi vsphere-csi-controller-*` | Check vsphere-config-secret; verify vCenter credentials; check TLS cert |
| vSAN disk latency spike | Grafana vSAN dashboard shows >5ms | Check vSAN health in vCenter; check disk rebuild status; evacuate VMs if disk failing |
| PV not detaching | Volume stuck in Terminating | Check if `open-vm-tools` is installed on node VM; restart `kubelet` on affected node |
| StorageClass FTT mismatch | PVC uses wrong policy | Explicitly set `storageClassName` in PVC spec; don't rely on default class for databases |
| vSAN out of space | PVC creation fails | Check vSAN capacity in vCenter; delete old snapshots; move to RAID-5 policy to save space |

---

## 7. vSAN Architecture Diagram

```
6-Node vSAN Cluster — All-Flash Configuration

Node 1          Node 2          Node 3
+----------+   +----------+   +----------+
| NVMe     |   | NVMe     |   | NVMe     |  ← Cache tier (write buffer)
| 800GB    |   | 800GB    |   | 800GB    |
+----------+   +----------+   +----------+
| SSD      |   | SSD      |   | SSD      |  ← Capacity tier (persistent)
| 1.92TB x4|   | 1.92TB x4|   | 1.92TB x4|
+----------+   +----------+   +----------+
     |               |               |
     +-------+-------+-------+-------+
                     |
           vSAN Distributed Storage
           (single namespace, all nodes)
           Total raw: ~46TB
           Usable (FTT=1): ~23TB

Node 4          Node 5          Node 6
+----------+   +----------+   +----------+
| NVMe     |   | NVMe     |   | NVMe     |
| 800GB    |   | 800GB    |   | 800GB    |
+----------+   +----------+   +----------+
| SSD      |   | SSD      |   | SSD      |
| 1.92TB x4|   | 1.92TB x4|   | 1.92TB x4|
+----------+   +----------+   +----------+
```

---

## 8. Storage Policy — When to Use What

| Policy | FTT | Method | Overhead | Use For | Min Nodes |
|--------|-----|--------|----------|---------|-----------|
| `vsan-dev-qa` | 0 | None | 0% | Dev/QA non-critical data | 1 |
| `vsan-production` | 1 | RAID-1 Mirror | 2x storage | PreProd, Prod workloads | 3 |
| `vsan-databases` | 1 | RAID-5 Erasure | 1.33x storage | PostgreSQL, MongoDB data disks | 4 |

```
FTT explained:
  FTT = 0: No fault tolerance. One disk failure = data loss. OK for Dev/QA only.
  FTT = 1 RAID-1: 2 copies on different hosts. One host can fail. Recommended for Prod.
  FTT = 1 RAID-5: Data + parity across 4 nodes. More efficient than RAID-1 for large data.
                   Best for large DB disks where storage efficiency matters.
```

---

## 9. Create Storage Policies via vCenter (Step-by-Step)

```
vCenter UI Path:
  Home → Policies and Profiles → VM Storage Policies → Create

Policy 1: vsan-dev-qa
  Name: vsan-dev-qa
  Description: Dev and QA — No fault tolerance, maximum performance
  Rules:
    → Add Rule: VSAN → Failures to tolerate: 0
    → Add Rule: VSAN → Failure tolerance method: No data redundancy
  Click Finish

Policy 2: vsan-production
  Name: vsan-production
  Description: PreProd and Production — RAID-1 mirroring, tolerates 1 failure
  Rules:
    → Add Rule: VSAN → Failures to tolerate: 1
    → Add Rule: VSAN → Failure tolerance method: RAID-1 (Mirroring)
    → Add Rule: VSAN → Number of disk stripes per object: 2
  Click Finish

Policy 3: vsan-databases
  Name: vsan-databases
  Description: Database volumes — RAID-5 erasure, efficient for large data
  Rules:
    → Add Rule: VSAN → Failures to tolerate: 1
    → Add Rule: VSAN → Failure tolerance method: RAID-5 (Erasure Coding)
    → Add Rule: VSAN → Number of disk stripes per object: 4
  Click Finish
```

---

## 10. vSphere CSI Driver — Full Installation

### 10.1 Prerequisites on All K8s VMs

```bash
# CRITICAL: disk.EnableUUID must be TRUE on every K8s VM
# Check via govc (from jump host):
for VM in k8s-master-1 k8s-master-2 k8s-master-3 \
          k8s-worker-1 k8s-worker-2 k8s-worker-3 \
          k8s-worker-4 k8s-worker-5 k8s-worker-6; do
  echo -n "$VM: "
  govc vm.info -e "$VM" | grep -i "disk.enable"
done
# All should show: disk.enableUUID = TRUE
# If not: govc vm.change -vm=<name> -e "disk.enableUUID=TRUE"
```

### 10.2 Create vCenter Credentials Secret

```bash
# Create CSI config file
cat > /tmp/csi-vsphere.conf << EOF
[Global]
cluster-id = "vxrail-k8s-cluster"

[VirtualCenter "vcenter.internal.company.com"]
insecure-flag = "false"
user = "csi-user@vsphere.local"
password = "CSIUserPassword123!"
port = "443"
datacenters = "Datacenter"
EOF

# Create K8s secret
kubectl create secret generic vsphere-config-secret \
  --from-file=csi-vsphere.conf=/tmp/csi-vsphere.conf \
  --namespace=vmware-system-csi

# Clean up local file
rm /tmp/csi-vsphere.conf
```

### 10.3 Create a Dedicated vCenter User for CSI

```
In vCenter: Administration → Single Sign-On → Users and Groups → Add User
  Username: csi-user
  Password: CSIUserPassword123!
  Domain: vsphere.local

Grant permissions (via Global Permissions):
  vCenter level: Read-only + specific privileges:
    Datastore: Allocate space, Browse datastore, Low level file operations
    Host: Local operations → Reconfigure VM
    Virtual machine: Configuration → Add existing disk, Add or remove device
    vSAN: Cluster → ShallowRekey
```

### 10.4 Install vSphere CSI Driver

```bash
# Apply CRDs and driver
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v3.3.0/manifests/vanilla/vsphere-7.0u3/deploy/vsphere-csi-crds.yaml

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v3.3.0/manifests/vanilla/vsphere-7.0u3/deploy/vsphere-csi-controller-deployment.yaml

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v3.3.0/manifests/vanilla/vsphere-7.0u3/deploy/vsphere-csi-node-ds.yaml

# Verify pods are running
kubectl get pods -n vmware-system-csi
# Expected:
# vsphere-csi-controller-xxxx   Running
# vsphere-csi-node-xxxx         Running (one per K8s node)
```

### 10.5 Create StorageClass YAML

```yaml
# storage-classes.yaml
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsan-dev-qa
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.vsphere.volume
parameters:
  storagepolicyname: "vsan-dev-qa"
  datastoreurl: "ds:///vmfs/volumes/vsan:xxxxxxxx/"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsan-production
provisioner: csi.vsphere.volume
parameters:
  storagepolicyname: "vsan-production"
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsan-databases
provisioner: csi.vsphere.volume
parameters:
  storagepolicyname: "vsan-databases"
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

```bash
kubectl apply -f storage-classes.yaml
kubectl get storageclass
```

### 10.6 Test PVC Creation

```yaml
# test-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: vsan-dev-qa
  resources:
    requests:
      storage: 5Gi
```

```bash
kubectl apply -f test-pvc.yaml
kubectl get pvc test-pvc
# STATUS should change from Pending → Bound within 30 seconds
# If stuck Pending: check CSI controller logs
kubectl logs -n vmware-system-csi -l app=vsphere-csi-controller -c vsphere-csi-controller

# Clean up test
kubectl delete pvc test-pvc
```

---

## 11. vSAN Health Monitoring

```bash
# From vCenter UI:
# Cluster → Monitor → vSAN → Health
# Run health check and look for:
#   Green: Cluster health, Disk balance, Network health
#   Yellow warnings are normal (e.g., "vSAN Build Recommendation")
#   Red alerts need immediate attention

# Common vSAN health check via esxcli (on any ESXi host):
ssh root@10.0.1.21
esxcli vsan health cluster list
esxcli vsan storage list   # Show all disk groups
esxcli vsan debug object list   # Show all vSAN objects

# From jump host via govc:
govc datastore.info vsanDatastore
# Shows: capacity, free space, type

# Check vSAN resync (after a disk/host failure and replacement)
govc cluster.usage -cluster=VxRail-Cluster
```

