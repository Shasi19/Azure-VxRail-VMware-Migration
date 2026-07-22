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
