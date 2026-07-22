# 04 — Storage Setup (Bare-Metal)

> **Goal**: Deploy MinIO distributed (replaces Azure Storage Account) and configure NFS StorageClass (backed by NetApp AFF A250) for Kubernetes persistent volumes.  
> These steps are identical to the KVM version — the difference is MinIO runs directly on physical server-db nodes rather than VMs.

---

## 1. Prepare Dedicated Data Disks

On bare-metal, MinIO uses raw NVMe disks for maximum performance.

```bash
# On each server-db-0x, identify the dedicated data disks (not the OS disk)
lsblk
# Example output:
# NAME      SIZE   TYPE
# nvme0n1   500G   disk   <- OS disk (already mounted)
# nvme1n1   4T     disk   <- Data disk for MinIO
# nvme2n1   4T     disk   <- Data disk for MinIO

# Format data disks with XFS (MinIO recommended)
mkfs.xfs /dev/nvme1n1
mkfs.xfs /dev/nvme2n1

mkdir -p /data/minio/disk1
mkdir -p /data/minio/disk2

# Get disk UUIDs (use UUID not device names for stability)
blkid /dev/nvme1n1
blkid /dev/nvme2n1

# Add to fstab using UUIDs
echo "UUID=<uuid-of-nvme1n1>  /data/minio/disk1  xfs  defaults,noatime  0 0" >> /etc/fstab
echo "UUID=<uuid-of-nvme2n1>  /data/minio/disk2  xfs  defaults,noatime  0 0" >> /etc/fstab

mount -a
df -h /data/minio/disk1
```

---

## 2. Install MinIO (Distributed Mode — 3 Nodes x 2 Drives = 6 Drives)

MinIO erasure coding requires minimum 4 drives total. With 3 servers x 2 drives = 6 drives, it survives 3 drive failures.

```bash
# Install MinIO binary on all 3 DB servers
wget https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
chmod +x /usr/local/bin/minio
minio --version

# Create MinIO user
useradd -r -s /sbin/nologin minio
chown -R minio:minio /data/minio

# Configure MinIO (same on all 3 servers)
cat > /etc/default/minio << 'EOF'
MINIO_VOLUMES="http://server-db-0{1...3}/data/minio/disk{1...2}"
MINIO_OPTS="--console-address :9001"
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=MinIO-OnPrem-2026!
MINIO_SITE_NAME=onprem-baremetal
EOF

# Create systemd service
cat > /etc/systemd/system/minio.service << 'EOF'
[Unit]
Description=MinIO Object Storage
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/usr/local/
User=minio
Group=minio
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server $MINIO_VOLUMES $MINIO_OPTS
Restart=always
RestartSec=5
LimitNOFILE=1048576
TasksMax=infinity
TimeoutStopSec=infinity
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now minio
systemctl status minio --no-pager
```

---

## 3. Configure MinIO Buckets

```bash
# Install MinIO client
wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# Configure alias pointing to any one of the nodes
mc alias set onprem http://10.0.1.30:9000 minioadmin MinIO-OnPrem-2026!
mc admin info onprem

# Create buckets per environment
mc mb onprem/dev-storage
mc mb onprem/qa-storage
mc mb onprem/preprod-storage
mc mb onprem/prod-storage
mc mb onprem/harbor-registry
mc mb onprem/velero-backups
mc mb onprem/db-backups

# Set lifecycle policy: auto-delete dev/qa backups after 30 days
mc ilm import onprem/dev-storage << 'EOF'
{"Rules":[{"ID":"auto-expire","Status":"Enabled","Expiration":{"Days":30}}]}
EOF

mc ls onprem
```

---

## 4. NFS StorageClass (NetApp AFF A250)

```bash
# Install NFS CSI driver
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update

helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --set kubeletDir=/var/lib/kubelet

# Create StorageClass
cat > /tmp/netapp-sc.yaml << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: netapp-nfs
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: nfs.csi.k8s.io
parameters:
  server: 10.0.3.10
  share: /vol/k8s_data
  subdir: ${pvc.metadata.namespace}/${pvc.metadata.name}
reclaimPolicy: Retain
volumeBindingMode: Immediate
allowVolumeExpansion: true
mountOptions:
  - nfsvers=4.1
  - hard
  - intr
  - rsize=131072
  - wsize=131072
EOF

kubectl apply -f /tmp/netapp-sc.yaml
kubectl get storageclass
```

---

## 5. Expose MinIO to Kubernetes

```bash
cat > /tmp/minio-endpoints.yaml << 'EOF'
apiVersion: v1
kind: Endpoints
metadata:
  name: minio-external
  namespace: default
subsets:
  - addresses:
      - ip: 10.0.1.30
      - ip: 10.0.1.31
      - ip: 10.0.1.32
    ports:
      - port: 9000
        protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: minio-external
  namespace: default
spec:
  ports:
    - port: 9000
      targetPort: 9000
  clusterIP: None
EOF

kubectl apply -f /tmp/minio-endpoints.yaml

# MinIO credentials as K8s secrets
for NS in dev qa preprod prod; do
  kubectl create secret generic minio-credentials \
    --namespace=$NS \
    --from-literal=accessKey=minioadmin \
    --from-literal=secretKey='MinIO-OnPrem-2026!' \
    --from-literal=endpoint=http://minio-external.default.svc.cluster.local:9000 \
    --from-literal=bucket=${NS}-storage
done
```

---

## 6. Performance Tuning — Bare-Metal NVMe

```bash
# Optimise NVMe queues for MinIO
for NVME in /sys/block/nvme*; do
  echo mq-deadline > $NVME/queue/scheduler
  echo 512 > $NVME/queue/nr_requests
done

# Increase max open files for MinIO
cat >> /etc/security/limits.conf << 'EOF'
minio soft nofile 1048576
minio hard nofile 1048576
EOF

# Verify MinIO performance (approximate throughput test)
mc admin trace onprem 2>/dev/null &
dd if=/dev/zero bs=1M count=1000 | mc pipe onprem/dev-storage/perf-test
mc rm onprem/dev-storage/perf-test
```

---

## 7. Verify Storage

```bash
echo "=== MinIO Cluster Health ==="
curl -s http://10.0.1.30:9000/minio/health/live && echo "Node 1 OK"
curl -s http://10.0.1.31:9000/minio/health/live && echo "Node 2 OK"
curl -s http://10.0.1.32:9000/minio/health/live && echo "Node 3 OK"
mc admin info onprem

echo "=== NFS StorageClass ==="
kubectl get storageclass

echo "=== PVC Test ==="
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-test
  namespace: dev
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: netapp-nfs
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc storage-test -n dev
kubectl delete pvc storage-test -n dev
```

---

*Next: [05-Database-Setup.md](05-Database-Setup.md)*
