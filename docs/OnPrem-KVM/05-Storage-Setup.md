# 05 — Storage Setup (KVM)

> **Goal**: Deploy MinIO (replaces Azure Storage Account) and configure the NFS StorageClass (backed by NetApp AFF A250) for Kubernetes persistent volumes.

---

## 1. MinIO Distributed Setup (Replaces Azure Storage Account)

MinIO runs as a 4-node distributed cluster for erasure coding (data survives 2 node failures).

### 1a. Create MinIO VMs or Use Infra VMs

```bash
# MinIO can run on the same infra VMs or dedicated ones
# Each MinIO node needs a dedicated data disk
# On each host, create a MinIO data disk for its infra VM:

qemu-img create -f qcow2 /data/kvm/images/minio-disk.qcow2 2000G

# Attach the disk to the infra VM
virsh attach-disk infra-db-01 \
  /data/kvm/images/minio-disk.qcow2 \
  vdb \
  --driver qemu \
  --subdriver qcow2 \
  --persistent

# Inside the VM: format and mount
mkfs.xfs /dev/vdb
mkdir -p /data/minio
echo '/dev/vdb /data/minio xfs defaults,noatime 0 0' >> /etc/fstab
mount -a
```

### 1b. Install MinIO Server on All 3 Infra VMs

```bash
# Run on infra-db-01, infra-db-02, infra-db-03
wget https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x minio
mv minio /usr/local/bin/

# Create minio user
useradd -r -s /sbin/nologin minio
chown minio:minio /data/minio

# Create minio config
cat > /etc/default/minio << 'EOF'
MINIO_VOLUMES="http://infra-db-0{1...3}:9000/data/minio"
MINIO_OPTS="--console-address :9001"
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=MinIO-OnPrem-2026!
MINIO_SITE_NAME=onprem-cluster
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
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now minio

# Check status
systemctl status minio --no-pager
curl http://10.0.1.30:9000/minio/health/live && echo "MinIO OK"
```

### 1c. Create MinIO Buckets (One per Environment)

```bash
# Install MinIO client (mc)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc && mv mc /usr/local/bin/

# Configure mc
mc alias set onprem http://10.0.1.30:9000 minioadmin MinIO-OnPrem-2026!

# Create buckets matching Azure Storage containers
mc mb onprem/dev-storage
mc mb onprem/qa-storage
mc mb onprem/preprod-storage
mc mb onprem/prod-storage
mc mb onprem/harbor-registry    # Used by Harbor
mc mb onprem/velero-backups     # Used by Velero
mc mb onprem/minio-backups

# Set bucket policies (env buckets = private)
mc anonymous set none onprem/dev-storage
mc anonymous set none onprem/prod-storage

# List buckets
mc ls onprem
```

---

## 2. NFS StorageClass for Kubernetes (NetApp AFF A250)

Kubernetes needs persistent volumes for databases, Harbor, and other stateful services.

### 2a. Install NFS CSI Driver in Kubernetes

```bash
# On k8s-cp-01
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update

helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --set kubeletDir=/var/lib/kubelet

kubectl get pods -n kube-system | grep nfs
```

### 2b. Create StorageClass for NetApp NFS

```bash
cat > /tmp/storage-class.yaml << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: netapp-nfs
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: nfs.csi.k8s.io
parameters:
  server: 10.0.3.10        # NetApp management IP
  share: /vol/k8s_data
  subdir: ${pvc.metadata.namespace}/${pvc.metadata.name}
reclaimPolicy: Retain
volumeBindingMode: Immediate
allowVolumeExpansion: true
mountOptions:
  - nfsvers=4.1
  - hard
  - intr
  - rsize=65536
  - wsize=65536
  - timeo=600
EOF

kubectl apply -f /tmp/storage-class.yaml

# Verify
kubectl get storageclass
```

### 2c. Test PVC Creation

```bash
cat > /tmp/test-pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-nfs-pvc
  namespace: dev
spec:
  accessModes: [ReadWriteMany]
  storageClassName: netapp-nfs
  resources:
    requests:
      storage: 1Gi
EOF

kubectl apply -f /tmp/test-pvc.yaml
kubectl get pvc -n dev
# Status should change to Bound within 30s

# Clean up test
kubectl delete pvc test-nfs-pvc -n dev
```

---

## 3. MinIO StorageClass (for S3-backed PVCs)

Some apps use S3 directly. Expose MinIO via a Kubernetes service:

```bash
cat > /tmp/minio-service.yaml << 'EOF'
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
      protocol: TCP
  clusterIP: None
EOF

kubectl apply -f /tmp/minio-service.yaml

# Create MinIO credentials as K8s secret (per namespace)
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

## 4. KVM-Specific: Attach Additional Disks to VMs

If you need to expand a database or MinIO volume:

```bash
# Create additional disk
qemu-img create -f qcow2 /data/kvm/images/infra-db-01-data2.qcow2 1000G

# Attach to running VM (hot-add)
virsh attach-disk infra-db-01 \
  /data/kvm/images/infra-db-01-data2.qcow2 \
  vdc \
  --driver qemu \
  --subdriver qcow2 \
  --live \
  --persistent

# Inside the VM: partition, format, mount
lsblk
mkfs.xfs /dev/vdc
mkdir -p /data/extra
echo '/dev/vdc /data/extra xfs defaults,noatime 0 0' >> /etc/fstab
mount -a
```

---

## 5. Verify Storage

```bash
# MinIO health check
curl http://10.0.1.30:9000/minio/health/live
mc admin info onprem

# NFS StorageClass
kubectl get storageclass
kubectl describe storageclass netapp-nfs

# Create a full test with pod
kubectl run storage-test \
  --image=nginx \
  --restart=Never \
  -n dev \
  --overrides='
  {
    "spec": {
      "volumes": [{"name": "pv", "persistentVolumeClaim": {"claimName": "storage-test-pvc"}}],
      "containers": [{"name": "nginx", "image": "nginx", "volumeMounts": [{"mountPath": "/data", "name": "pv"}]}]
    }
  }'
```

---

*Next: [06-Database-Setup.md](06-Database-Setup.md)*
